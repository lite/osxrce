/***********************************************************************
 * NAME
 *      inject_bundle -- Inject a dynamic library or bundle into a
 *                       running process
 *
 * SYNOPSIS
 *      inject_bundle path_to_bundle [ pid ]
 *
 * DESCRIPTION
 *      The inject_bundle utility injects a dynamic library or bundle
 *      into another process.  It does this by acquiring access to the
 *      remote process' mach task port (via task_for_pid()) and
 *      creating a new thread to call dlopen().  If the dylib or
 *      bundle exports a function called "run", it will be called
 *      separately.
 * 
 * EXIT STATUS
 *      Exits 0 on success, -1 on error.
 **********************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdarg.h>
#include <err.h>

#include <dlfcn.h>
#include <mach/mach.h>
#include <mach/mach_error.h>
#include <pthread.h>
#include <sys/param.h>

#define __i386__ 1

#if defined(__ppc__) || defined(__ppc64__)
#include <architecture/ppc/cframe.h>
#endif

/*
 * If this symbol is exported from the bundle, it will be called
 * separately after initialization.
 */
#define BUNDLE_MAIN "run"

/***********************************************************************
 * Mach Exceptions
 ***********************************************************************/

extern boolean_t exc_server(mach_msg_header_t *request,
                            mach_msg_header_t *reply);

/*
 * From: xnu/bsd/uxkern/ux_exception.c
 */
typedef struct {
    mach_msg_header_t header;
    mach_msg_body_t body;
    mach_msg_port_descriptor_t thread;
    mach_msg_port_descriptor_t task;
    NDR_record_t NDR;
    exception_type_t exception;
    mach_msg_type_number_t code_count;
    mach_exception_data_t code;
    char pad[512];
} exc_msg_t;

/**********************************************************************
 * Remote task memory
 **********************************************************************/
kern_return_t
remote_copyout(task_t task, void* src, vm_address_t dest, size_t n);

kern_return_t
remote_copyin(task_t task, vm_address_t src, void* dest, size_t n);

extern vm_address_t
remote_malloc(task_t task, size_t size);
    
extern kern_return_t
remote_free(task_t task, vm_address_t addr);

kern_return_t
remote_copyout(mach_port_t task, void* src, vm_address_t dest, size_t n)
{
    kern_return_t kr = KERN_SUCCESS;
    void* buf;
    
    // vm_write needs to copy data from a page-aligned buffer
    buf = malloc((n + PAGE_SIZE) & ~PAGE_SIZE);
    memcpy(buf, src, n);
    
    if ((kr = vm_write(task, dest, (vm_offset_t)buf, n))) {
        return kr;
    }

    free(buf);

    return kr;
}

kern_return_t
remote_copyin(mach_port_t task, vm_address_t src, void* dest, size_t n)
{
    kern_return_t kr = KERN_SUCCESS;
    vm_size_t size = n;
    
    if ((kr = vm_read_overwrite(task, src, n, (vm_offset_t)dest, &size))) {
        return kr;
    }

    return kr;
}

vm_address_t
remote_malloc(mach_port_t task, size_t size)
{
    kern_return_t kr = KERN_SUCCESS;
    vm_address_t addr;
    
    if ((kr = vm_allocate(task, &addr, size + sizeof(size), TRUE)))
        return (vm_address_t)NULL;

    /*
     * Write allocation size into first bytes of remote page
     */
    if (remote_copyout(task, &size, addr, sizeof(size))) {
        vm_deallocate(task, addr, size);
        return (vm_address_t)NULL;
    }

    return addr + sizeof(size);
}

kern_return_t
remote_free(mach_port_t task, vm_address_t addr)
{
    kern_return_t kr = KERN_SUCCESS;
    size_t size;
    
    /*
     * Read allocation size from remote memory
     */
    if ((kr = remote_copyin(task, addr - sizeof(size), &size, sizeof(size)))) {
        return kr;
    }

    kr = vm_deallocate(task, addr - sizeof(size), size);
    return kr;
}

/**********************************************************************
 * Remote threads
 **********************************************************************/

typedef enum {
    UNINIT,       // Remote thread not yet initialized (error returned)
    CREATED,      // Thread and remote stack created and allocated
    RUNNING,      // Thread is running
    SUSPENDED,    // Thread suspended, but still allocated
    TERMINATED    // Thread terminated and remote stack deallocated
} remote_thread_state_t;

typedef struct {
    remote_thread_state_t state;
    task_t                task;
    thread_t              thread;
    vm_address_t          stack;
    size_t                stack_size;
} remote_thread_t;

/*
 * This magic return address signals a return from the remote
 * function.  The Mach VM manager cannot map a page at 0xfffff000, so
 * this is guaranteed to always generate an EXC_BAD_ACCESS.
 */
#define MAGIC_RETURN 0xfffffba0
#define STACK_SIZE   (512*1024)
#define PTHREAD_SIZE (4096)    // Size to reserve for pthread_t struct

kern_return_t
create_remote_thread(mach_port_t task, remote_thread_t* rt, 
		     vm_address_t start_address, int argc, ...);

kern_return_t
join_remote_thread(remote_thread_t* remote_thread, void** return_value);

// Called by exc_server()
kern_return_t catch_exception_raise_state_identity(
    mach_port_t exception_port,
    mach_port_t thread,
    mach_port_t task,
    exception_type_t exception,
    exception_data_t code,
    mach_msg_type_number_t code_count,
    int *flavor,
    thread_state_t old_state,
    mach_msg_type_number_t old_state_count,
    thread_state_t new_state,
    mach_msg_type_number_t *new_state_count)
{
    switch (*flavor) {
#if defined(__i386__)
    case x86_THREAD_STATE32:
	/*
	 * A magic value of EIP signals that the thread is done
	 * executing.  We respond by suspending the thread so that
	 * we can terminate the exception handling loop and
	 * retrieve the return value.
	 */
	if (((x86_thread_state32_t*)old_state)->__eip == MAGIC_RETURN) {
	    thread_suspend(thread);
            
	    /*
	     * Signal that exception was handled
	     */
	    return MIG_NO_REPLY;
	}
	
	break;
#elif defined(__ppc__)
    case PPC_THREAD_STATE:
	if (((ppc_thread_state_t*)old_state)->__srr0 == MAGIC_RETURN) {
	    thread_suspend(thread);
	    return MIG_NO_REPLY;
	}

	break;
#endif
    }

    /*
     * Otherwise, keep searching for an exception handler
     */
    return KERN_INVALID_ARGUMENT;
}

kern_return_t
join_remote_thread(remote_thread_t* remote_thread, void** return_value)
{
    kern_return_t kr;
    mach_port_t exception_port;
    thread_basic_info_data_t thread_basic_info;
    mach_msg_type_number_t thread_basic_info_count = THREAD_BASIC_INFO_COUNT;

    // Allocate exception port
    if ((kr = mach_port_allocate(mach_task_self(),
                                 MACH_PORT_RIGHT_RECEIVE,
                                 &exception_port))) {
        errx(EXIT_FAILURE, "mach_port_allocate: %s", mach_error_string(kr));
    }

    if ((kr = mach_port_insert_right(mach_task_self(),
                                     exception_port, exception_port,
                                     MACH_MSG_TYPE_MAKE_SEND))) {
        errx(EXIT_FAILURE, "mach_port_insert_right: %s",
             mach_error_string(kr));
    }

    // Set remote thread's exception port
#if defined(__i386__)
    if ((kr = thread_set_exception_ports(remote_thread->thread,
                                         EXC_MASK_BAD_ACCESS,
                                         exception_port,
                                         EXCEPTION_STATE_IDENTITY,
                                         x86_THREAD_STATE32))) {
        errx(EXIT_FAILURE, "thread_set_exception_ports: %s",
             mach_error_string(kr));
    }
#elif defined(__ppc__)
    if ((kr = thread_set_exception_ports(remote_thread->thread,
                                         EXC_MASK_BAD_ACCESS,
                                         exception_port,
                                         EXCEPTION_STATE_IDENTITY,
                                         PPC_THREAD_STATE))) {
        errx(EXIT_FAILURE, "thread_set_exception_ports: %s",
             mach_error_string(kr));
    }
#endif
    
    // Run thread
    if ((kr = thread_resume(remote_thread->thread))) {
        errx(EXIT_FAILURE, "thread_resume: %s", mach_error_string(kr));
    }

    remote_thread->state = RUNNING;
    
    /*
     * Run exception handling loop until thread terminates
     */
    while (1) {
        if ((kr = mach_msg_server_once(exc_server, sizeof(exc_msg_t),
                                       exception_port,
                                       MACH_MSG_TIMEOUT_NONE))) {
            errx(EXIT_FAILURE, "mach_msg_server: %s", mach_error_string(kr));
        }

        if ((kr = thread_info(remote_thread->thread, THREAD_BASIC_INFO,
                              (thread_info_t)&thread_basic_info,
                              &thread_basic_info_count))) {
            errx(EXIT_FAILURE, "thread_info: %s", mach_error_string(kr));
        }
        
        if (thread_basic_info.suspend_count > 0) {
	    /*
	     * Retrieve return value from thread state
	     */
            remote_thread->state = SUSPENDED;
            
#if defined(__i386__)
	    x86_thread_state32_t remote_thread_state;
            mach_msg_type_number_t thread_state_count =
		x86_THREAD_STATE32_COUNT;

            if ((kr = thread_get_state(remote_thread->thread,
                                       x86_THREAD_STATE32,
                                       (thread_state_t)&remote_thread_state,
                                       &thread_state_count))) {
                errx(EXIT_FAILURE, "thread_get_state: %s",
                     mach_error_string(kr));
            }

            *return_value = (void*)remote_thread_state.__eax;
#elif defined(__ppc__)
	    ppc_thread_state_t remote_thread_state;
            mach_msg_type_number_t thread_state_count =
		PPC_THREAD_STATE_COUNT;

            if ((kr = thread_get_state(remote_thread->thread,
                                       PPC_THREAD_STATE,
                                       (thread_state_t)&remote_thread_state,
                                       &thread_state_count))) {
                errx(EXIT_FAILURE, "thread_get_state: %s",
                     mach_error_string(kr));
            }

            *return_value = (void*)remote_thread_state.__r3;
#endif
            if ((kr = thread_terminate(remote_thread->thread))) {
                errx(EXIT_FAILURE, "thread_terminate: %s",
                     mach_error_string(kr));
            }

            if ((kr = vm_deallocate(remote_thread->task,
                                    remote_thread->stack,
                                    remote_thread->stack_size))) {
                errx(EXIT_FAILURE, "vm_deallocate: %s",
                     mach_error_string(kr));
            }
            
            remote_thread->state = TERMINATED;

            break;
        }
    }

    return kr;
}

/*
 * Raw assembly code for trampolines.  If they are changed,
 * TRAMPOLINE_SIZE must be calculated manually and updated as well.
 * The asm keyword is an Apple GCC extension intended to resemble the
 * same feature in CodeWarrior and Visual Studio.
 */
#if defined(__i386__)
#define MACH_THREAD_TRAMPOLINE_SIZE (16)
asm void mach_thread_trampoline(void)
{
    // Call _pthread_set_self with pthread_t arg already on stack
    pop     eax
    call    eax
    add     esp, 4
        
    // Call cthread_set_self with pthread_t arg already on stack
    pop     eax
    call    eax
    add     esp, 4

    // Call function with return address and arguments already on stack
    pop     eax
    jmp     eax
}

#define PTHREAD_TRAMPOLINE_SIZE (4)
asm void pthread_trampoline(void)
{
    nop
    nop
    nop
    nop
}

#elif defined(__ppc__)
#define MACH_THREAD_TRAMPOLINE_SIZE (27*4)
/*
 * Expects:
 * r3  - struct _pthread *
 * r26 - start_routine arg
 * r27 - &(pthread_join)
 * r28 - &(pthread_create)
 * r29 - &(_pthread_set_self)
 * r30 - &(cthread_set_self)
 * r31 - &(start_routine)
 * ...
 */
asm void mach_thread_trampoline(void) 
{
    mflr    r0
    stw     r0, 8(r1)
    stwu    r1, -96(r1)
    stw     r3, 56(r1)
      
    // Call _pthread_set_self(pthread)
    mtctr   r29
    bctrl

    // Call cthread_set_self(pthread)
    lwz     r3, 56(r1)
    mtctr   r30
    bctrl

    // pthread_create(&pthread, NULL, start_routine, arg)  
    addi    r3, r1, 60
    xor     r4, r4, r4
    mr      r5, r31
    mr      r6, r26
    mtctr   r28
    bctrl

    // pthread_join(pthread, &return_value)
    lwz     r3, 60(r1)
    addi    r4, r1, 64
    mtctr   r27
    bctrl

    lwz     r3, 64(r1)
    lwz     r0, 96 + 8(r1)
    mtlr    r0
    addi    r1, r1, 96
    blr
}

/*
 * Loads argument and function pointer from single argument and calls
 * the specified function with those arguments.
 */
#define PTHREAD_TRAMPOLINE_SIZE (12*4)
asm void pthread_trampoline(void)
{
    mr      r2, r3
        
    lwz     r3, 0(r2)
    lwz     r4, 4(r2)
    lwz     r5, 8(r2)
    lwz     r6, 12(r2)
    lwz     r7, 16(r2)
    lwz     r8, 20(r2)
    lwz     r9, 24(r2)
    lwz     r10, 28(r2)

    lwz     r2, 32(r2)
    mtctr   r2
    bctr
}
#endif

/*
 * create_remote_thread -- Create the remote thread, but do not run it yet.
 * 
 * Actually creating the remote thread is tricky.  A naked mach thread
 * will crash when a function that it calls tries to access
 * thread-specific data.  Therefore, we must create a real pthread.
 * In order to do so, we create a remote mach thread to call
 * pthread_create with a small assembly trampoline as its start
 * routine.  The parameter to the start routine is a parameter block
 * that contains the address of the function that the user really
 * wanted to call and any parameters to that function.
 *
 * pthread_create() will return into a second trampoline that calls
 * pthread_join() on the newly created thread.
 */
kern_return_t
create_remote_thread(mach_port_t task, remote_thread_t* rt, 
		     vm_address_t start_address, int argc, ...)
{
    va_list ap;
    int i;
    kern_return_t kr;
    thread_t remote_thread;
    vm_address_t remote_stack, pthread,
	mach_thread_trampoline_code, pthread_trampoline_code;
    size_t stack_size = STACK_SIZE;
    unsigned long* stack, *sp;
    static void (*pthread_set_self)(pthread_t) = NULL;
    static void (*cthread_set_self)(void*) = NULL;

    /*
     * Initialize remote_thread_t
     */
    rt->state = UNINIT;
    rt->task = rt->thread = 0;
    rt->stack = rt->stack_size = 0;

    if (argc > 8) {
	// We don't handle that many arguments
	return KERN_FAILURE;
    }
    
    /*
     * Cheat and look up the private function _pthread_set_self().  We
     * need to call this in the created remote thread in order to
     * make it a real pthread.  Many library functions fail if they
     * are called from a basic mach thread.
     */
    if (pthread_set_self == NULL) {
	pthread_set_self = (void (*)(pthread_t))
	    dlsym(RTLD_DEFAULT, "__pthread_set_self");
    }

    if (cthread_set_self == NULL) {
	cthread_set_self = (void (*)(void*))
	    dlsym(RTLD_DEFAULT, "cthread_set_self");
    }

    /*
     * Allocate remote and local (temporary copy) stacks
     */
    if ((kr = vm_allocate(task, &remote_stack, stack_size, TRUE)))
        return kr;
    
    stack = malloc(stack_size);
    sp = (unsigned long*)((char*)stack + stack_size);

    /*
     * Allocate space on the stack for a pthread structure
     */
    sp = (unsigned long*)
	((char*)sp - PTHREAD_SIZE);
    pthread = remote_stack + (vm_address_t)sp - (vm_address_t)stack;
    
    /*
     * Copy over trampoline code to call intended function
     */
    sp = (unsigned long*)((char*)sp - MACH_THREAD_TRAMPOLINE_SIZE);
    memcpy(sp, &mach_thread_trampoline, MACH_THREAD_TRAMPOLINE_SIZE);
    mach_thread_trampoline_code =
	remote_stack + (vm_address_t)sp - (vm_address_t)stack;

    /*
     * Copy over trampoline code to call intended function
     */
    sp = (unsigned long*)((char*)sp - PTHREAD_TRAMPOLINE_SIZE);
    memcpy(sp, &pthread_trampoline, PTHREAD_TRAMPOLINE_SIZE);
    pthread_trampoline_code =
	remote_stack + (vm_address_t)sp - (vm_address_t)stack;
    
    // Create remote thread suspended
    if ((kr = thread_create(task, &remote_thread))) {
        errx(EXIT_FAILURE, "thread_create: %s", mach_error_string(kr));
    }

#if defined(__i386__)
    {
	x86_thread_state32_t remote_thread_state;
        vm_address_t remote_sp;
        unsigned long* args;  
        /*
         * Stack must be 16-byte aligned when we call the target
         * function.  Otherwise, if we call dlopen(), we may get a
         * misaligned stack error.
         */
        sp -= argc;
        sp -= ((unsigned int)sp % 16) / sizeof(*sp);
        
        args = sp;
        
        va_start(ap, argc);
        for (i = 0; i < argc; i++) {
            unsigned long arg = va_arg(ap, unsigned long);
            *(args + i) = arg;
        }
        va_end(ap);
        
	// Push magic return address and start address onto stack
	*(--sp) = MAGIC_RETURN;
        *(--sp) = (unsigned long)start_address;
        
        // Push pthread_t arg and address of cthread_set_self
        *(--sp) = pthread;
        *(--sp) = (unsigned long)cthread_set_self;
        
        // Push pthread_t arg and address of pthread_set_self
        *(--sp) = pthread;
        *(--sp) = (unsigned long)pthread_set_self;

        remote_sp = remote_stack + (vm_address_t)sp - (vm_address_t)stack;
        
        /*
         * Copy local stack to remote stack
         */
        if ((kr = vm_write(task, remote_stack,
                           (pointer_t)stack, stack_size))) {
            errx(EXIT_FAILURE, "vm_write: %s", mach_error_string(kr));
        }
        
	// Initialize thread state
	bzero(&remote_thread_state, sizeof(remote_thread_state));
	
	remote_thread_state.__eip = mach_thread_trampoline_code;
	remote_thread_state.__esp = remote_sp;
        
	if ((kr = thread_set_state(remote_thread, x86_THREAD_STATE32,
                                   (thread_state_t)&remote_thread_state,
                                   x86_THREAD_STATE32_COUNT))) {
	    errx(EXIT_FAILURE, "thread_set_state: %s", mach_error_string(kr));
	}
    }
#elif defined(__ppc__)
    {
	ppc_thread_state_t remote_thread_state;
        vm_address_t remote_sp;
        unsigned long* start_arg;

        /*
         * Build parameter block for pthread_trampoline
         */
        *(--sp) = start_address;
        sp -= 8;
        start_arg = sp;
        
        va_start(ap, argc);
        for (i = 0; i < argc; i++) {
            unsigned long arg = va_arg(ap, unsigned long);
            *(sp + i) = arg;
        }
        va_end(ap);

        sp -= ((unsigned int)sp % 16) / sizeof(*sp);
        
        /*
         * Copy local stack to remote stack
         */
        if ((kr = vm_write(task, remote_stack,
                           (pointer_t)stack, stack_size))) {
            errx(EXIT_FAILURE, "vm_write: %s", mach_error_string(kr));
        }
        
	/*
	 * Set registers
	 */
        // XXX: C_ARGSAVE_LEN and C_RED_ZONE are probably unnecessary
        remote_sp = remote_stack + (vm_address_t)sp - (vm_address_t)stack -
            C_ARGSAVE_LEN - C_RED_ZONE;

	bzero(&remote_thread_state, sizeof(remote_thread_state));

	remote_thread_state.__srr0 = mach_thread_trampoline_code;
	remote_thread_state.__r1   = remote_sp;
	remote_thread_state.__r3   = pthread;

        remote_thread_state.__r26  =
            remote_stack + (vm_address_t)start_arg - (vm_address_t)stack;

	remote_thread_state.__r27  = (unsigned int)pthread_join;
	remote_thread_state.__r28  = (unsigned int)pthread_create;
	remote_thread_state.__r29  = (unsigned int)pthread_set_self;
	remote_thread_state.__r30  = (unsigned int)cthread_set_self;
	remote_thread_state.__r31  = (unsigned int)pthread_trampoline_code;

	remote_thread_state.__lr   = MAGIC_RETURN;

	// Initialize thread
	if ((kr = thread_set_state(remote_thread, PPC_THREAD_STATE,
                                   (thread_state_t)&remote_thread_state,
                                   PPC_THREAD_STATE_COUNT))) {
	    errx(EXIT_FAILURE, "thread_set_state: %s", mach_error_string(kr));
	}
    }
#endif

    rt->state = CREATED;
    rt->task = task;
    rt->thread = remote_thread;
    rt->stack = remote_stack;
    rt->stack_size = stack_size;
    
    return kr;
}

/**********************************************************************
 * Bundle injection
 **********************************************************************/

kern_return_t
remote_getpid(task_t task, pid_t* pid)
{
    kern_return_t kr;
    remote_thread_t thread;
    
    if ((kr = create_remote_thread(task, &thread,
                                   (vm_address_t)&getpid, 0))) {
        warnx("create_remote_thread() failed: %s", mach_error_string(kr));
        return kr;
    }

    if ((kr = join_remote_thread(&thread, (void**)pid))) {
        warnx("join_remote_thread() failed: %s", mach_error_string(kr));
        return kr;
    }

    return kr;
}

kern_return_t
inject_bundle(task_t task, const char* bundle_path, void** return_value)
{
    kern_return_t kr;
    char path[PATH_MAX];
    vm_address_t path_rptr, sub_rptr;
    remote_thread_t thread;
    void* dl_handle = 0, *sub_addr = 0;

    /*
     * Since the remote process may have a different working directory
     * and library path environment variables, we must load the bundle
     * via a canonical absolute path.
     */
    if (!realpath(bundle_path, path)) {
        warn("realpath");
        return KERN_FAILURE;
    }
    
    /*
     * dl_handle = dlopen(path, RTLD_NOW | RTLD_LOCAL)
     */
    path_rptr = remote_malloc(task, sizeof(path));
    remote_copyout(task, path, path_rptr, sizeof(path));

    if ((kr = create_remote_thread(task, &thread,
                                   (vm_address_t)&dlopen, 2,
                                   path_rptr, RTLD_NOW | RTLD_LOCAL))) {
	warnx("create_remote_thread dlopen() failed: %s",
              mach_error_string(kr));
        return kr;
    }

    if ((kr = join_remote_thread(&thread, &dl_handle))) {
	warnx("join_remote_thread dlopen() failed: %s",
              mach_error_string(kr));
        return kr;
    }

    remote_free(task, path_rptr);

    if (dl_handle == NULL) {
        warnx("dlopen() failed");
        return KERN_FAILURE;
    }
    
    /*
     * sub_addr = dlsym(dl_handle, "run")
     */
    sub_rptr = remote_malloc(task, strlen(BUNDLE_MAIN) + 1);
    remote_copyout(task, BUNDLE_MAIN, sub_rptr, strlen(BUNDLE_MAIN) + 1);

    if ((kr = create_remote_thread(task, &thread,
                                   (vm_address_t)&dlsym, 2,
                                   dl_handle, sub_rptr))) {
        warnx("create_remote_thread dlsym() failed: %s",
              mach_error_string(kr));
        return kr;
    }

    if ((kr = join_remote_thread(&thread, &sub_addr))) {
	warnx("join_remote_thread dlsym() failed: %s",
              mach_error_string(kr));
        return kr;
    }

    remote_free(task, sub_rptr);

    if (sub_addr) {
        /*
         * return_value = run()
         */
        if ((kr = create_remote_thread(task, &thread,
                                       (vm_address_t)sub_addr, 0))) {
            warnx("create_remote_thread run() failed: %s",
                   mach_error_string(kr));
            return kr;
        }
        
        if ((kr = join_remote_thread(&thread, return_value))) {
            warnx("join_remote_thread run() failed: %s",
                  mach_error_string(kr));
            return kr;
        }
        
        return (int)return_value;
    }

    return kr;
}

int main(int argc, char* argv[])
{
    pid_t pid;
    kern_return_t kr;
    task_t task;
    void* return_value;
    
    if (argc < 2) {
        fprintf(stderr, "usage: %s <path to bundle> [<pid>]\n", argv[0]);
        exit(EXIT_FAILURE);
    }

    if (argc == 3) {
        pid = atoi(argv[2]);
        if ((kr = task_for_pid(mach_task_self(), pid, &task))) {
            errx(EXIT_FAILURE, "task_for_pid: %s", mach_error_string(kr));
        }
    }
    else {
        task = mach_task_self();
    }
    
    inject_bundle(task, argv[1], &return_value);
    return (int)return_value;
}
