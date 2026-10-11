/*
 * sys/fileport.h — vendored（修复#10：新 iOS SDK 已移除该头，ClearSword socket.c 需要）
 * 声明按 XNU syscall 域原样（bsd/sys/fileport.h）：
 *   fileport_makeport → 把 file 描述符转成 mach send right
 *   fileport_makefd   → 逆变换
 * 内核号：SYS_fileport_makeport / SYS_fileport_makefd。
 */
#ifndef _SYS_FILEPORT_H_
#define _SYS_FILEPORT_H_

#include <stdint.h>
#include <mach/mach.h>

/* XNU 原义：fileport_t 即 mach_port_t（bsd/sys/fileport.h） */
typedef mach_port_t fileport_t;

__BEGIN_DECLS

extern kern_return_t fileport_makeport(int fd, fileport_t *port);
extern int fileport_makefd(fileport_t port);

__END_DECLS

#endif /* _SYS_FILEPORT_H_ */
