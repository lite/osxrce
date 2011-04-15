# GAS filename : hello.s
# use as to compile
# /Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/as -arch armv6 hello.s -o hello
# use otool to disassemble
# otool -tv hello

  .globl _main
  .code 16
  .thumb_func _main
_main:
  push {r7, lr}
  add r7, sp, #0
  add r3, pc
  mov ip, r3
  mov r3, ip
  mov r0, r3
  pop {r7, pc}

