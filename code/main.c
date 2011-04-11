#include <stdio.h>
#include <mach-o/nlist.h>
#include <dlfcn.h>
#include <CoreFoundation/CoreFoundation.h>

/* Path to the MobileDevice framework is used to look up symbols and offsets */
#define MOBILEDEVICE_FRAMEWORK "/System/Library/PrivateFrameworks/MobileDevice.framework/Versions/A/MobileDevice"

/* Used as a pointer to the iPhone/iTouch device, when booted into recovery */
typedef struct AMRecoveryModeDevice *AMRecoveryModeDevice_t;

/* Memory pointers to private functions inside the MobileDevice framework */
typedef int(*symbol)  (AMRecoveryModeDevice_t, CFStringRef) \
    __attribute__ ((regparm(2)));
static symbol sendCommandToDevice;
static symbol sendFileToDevice;

/* Very simple symbol lookup. Returns the position of the function in memory */
static unsigned int loadSymbol (const char *path, const char *name)
{
    struct nlist nl[2];
    memset(&nl, 0, sizeof(nl));
    nl[0].n_un.n_name = (char *) name;
    // nl[0].n_un.n_strx = (char *) name;
    if (nlist(path, nl) < 0 || nl[0].n_type == N_UNDF) {
        return 0;
    }
    return nl[0].n_value;
}

// static unsigned int loadSymbol (const char *path, const char *name)
// {
//     void* handle,*p;
//     handle = dlopen(path, RTLD_NOW);
//     if ( handle == NULL )
//         fprintf(stderr, dlerror());
//     p = dlsym(handle, name);
//     if ( p == NULL )
//         fprintf(stderr, dlerror());
//     return p;
// }
    
/* How to proceed when the device is connected in recovery mode.
* This is the function responsible for sending the ramdisk image and booting
* into the memory location containing it. */

void Recovery_Connect(AMRecoveryModeDevice_t device) {
    int r;

    fprintf(stderr, "Recovery_Connect: DEVICE CONNECTED in Recovery Mode\n");

    /* Upload RAM disk image from file */
    r = sendFileToDevice(device, CFSTR("ramdisk.bin"));
    fprintf(stderr, "sendFileToDevice returned %d\n", r);

    /* Set the boot environment arguments sent to the kernel */
    r = sendCommandToDevice(device,
        CFSTR("setenv boot-args rd=md0 -s -x pmd0=0x9340000.0xA00000"));
    fprintf(stderr, "sendCommandToDevice returned %d\n", r);

    /* Instruct the device to save the environment variable change */
    r = sendCommandToDevice(device, CFSTR("saveenv"));
    fprintf(stderr, "sendCommandToDevice returned %d\n", r);

    /* Invoke boot sequence (bootx may also be used) */
    r = sendCommandToDevice(device, CFSTR("fsboot"));
    fprintf(stderr, "sendCommandToDevice returned %d\n", r);
}

/* Used for notification only */
void Recovery_Disconnect(AMRecoveryModeDevice_t device) {

    fprintf(stderr, "Recovery_Disconnect: Device Disconnected\n");
}

/* Main program loop */
int main(int argc, char *argv[]) {
    AMRecoveryModeDevice_t recoveryModeDevice;
    unsigned int r;

    /* Find the __sendCommandToDevice and __sendFileToDevice symbols */
    
    // sendCommandToDevice = (symbol) loadSymbol(MOBILEDEVICE_FRAMEWORK, "_lockconn_send_message");
    sendCommandToDevice = (symbol) loadSymbol(MOBILEDEVICE_FRAMEWORK, "__sendCommandToDevice");
    if (!sendCommandToDevice) {
        fprintf(stderr, "ERROR: Could not locate symbol: __sendCommandToDevice in %s\n", MOBILEDEVICE_FRAMEWORK);
        return EXIT_FAILURE;
    }
    fprintf(stderr, "sendCommandToDevice: %08x\n", sendCommandToDevice);

    sendFileToDevice = (symbol) loadSymbol(MOBILEDEVICE_FRAMEWORK, "__sendFileToDevice");
    if (!sendFileToDevice) {
        fprintf(stderr, "ERROR: Could not locate symbol: __sendFileToDevice in %s\n", MOBILEDEVICE_FRAMEWORK);
        return EXIT_FAILURE;
    }

    /* Invoke callback functions for recovery mode connect and disconnect */
    r = AMRestoreRegisterForDeviceNotifications(
        NULL,
        Recovery_Connect,
        NULL,
        Recovery_Disconnect,
        0,
        NULL);
    fprintf(stderr, "AMRestoreRegisterForDeviceNotifications returned %d\n", 
    r);
    fprintf(stderr, "Waiting for device in restore mode...\n");

    /* Loop */
    CFRunLoopRun();
}