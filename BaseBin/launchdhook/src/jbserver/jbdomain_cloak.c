#include "jbserver_global.h"
#include "jbsettings.h"

#include <libjailbreak/codesign.h>
#include <libjailbreak/cloak.h>
#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/info.h>
#include <libproc.h>
#include <paths.h>
#include <string.h>
#include <stdlib.h>
#include <sys/param.h>

/*
 * Euphoria cloak domain (JBS_DOMAIN_CLOAK)
 *
 * GET_POLICY is intentionally reachable from every process: systemhook is
 * injected into every jailbroken process and needs the policy to know what
 * to filter for that process.  The mutating operations (ENABLE, DISABLE,
 * SET_OPTIONS, MOUNT_REPORT) re-verify that the caller is a platform binary
 * through the caller token, so an ordinary sandboxed app can never flip the
 * stealth state.
 */

bool gCloakMountActive = false;
char gCloakMountPoint[MAXPATHLEN] = { 0 };
char gCloakLastError[MAXPATHLEN] = { 0 };

static bool cloak_caller_is_platform(audit_token_t *callerToken)
{
        if (!callerToken) return false;

        // cloakd and jbctl run as root platform binaries; the Euphoria app is
        // authorized through its own domain.  Everything else must present the
        // CS_PLATFORM_BINARY code signing flag.
        pid_t pid = audit_token_to_pid(*callerToken);
        uint32_t csflags = 0;
        if (csops_audittoken(pid, CS_OPS_STATUS, &csflags, sizeof(csflags), callerToken) != 0) return false;
        return (csflags & CS_PLATFORM_BINARY);
}

static int cloak_get_policy(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8)
{
        if (a1) *(bool *)a1    = jbsetting(cloakEnabled);
        if (a2) *(bool *)a2    = jbsetting(cloakHideMounts);
        if (a3) *(bool *)a3    = jbsetting(cloakHideCredentials);
        if (a4) *(bool *)a4    = jbsetting(cloakHideTrustcache);
        if (a5) *(uint64_t *)a5 = jbsetting(cloakStealthLevel);
        if (a6) *(bool *)a6    = gCloakMountActive;
        if (a7) *(char **)a7   = strdup(gCloakMountPoint[0] ? gCloakMountPoint : "");
        if (a8) *(char **)a8   = strdup(gCloakLastError[0] ? gCloakLastError : "");
        return 0;
}

static int cloak_enable(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8)
{
        audit_token_t *callerToken = (audit_token_t *)a1;
        if (!cloak_caller_is_platform(callerToken)) return -2;

        gSystemInfo.jailbreakSettings.cloakEnabled = true;
        return 0;
}

static int cloak_disable(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8)
{
        audit_token_t *callerToken = (audit_token_t *)a1;
        if (!cloak_caller_is_platform(callerToken)) return -2;

        gSystemInfo.jailbreakSettings.cloakEnabled = false;
        return 0;
}

static int cloak_set_options(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8)
{
        audit_token_t *callerToken = (audit_token_t *)a1;
        if (!cloak_caller_is_platform(callerToken)) return -2;

        if (a2) gSystemInfo.jailbreakSettings.cloakHideMounts      = *(bool *)a2;
        if (a3) gSystemInfo.jailbreakSettings.cloakHideCredentials = *(bool *)a3;
        if (a4) gSystemInfo.jailbreakSettings.cloakHideTrustcache  = *(bool *)a4;
        if (a5) gSystemInfo.jailbreakSettings.cloakStealthLevel    = *(uint64_t *)a5;
        if (a6) gSystemInfo.jailbreakSettings.cloakBlacklistMode   = *(bool *)a6; // R40
        return 0;
}

static int cloak_mount_report(void *a1, void *a2, void *a3, void *a4, void *a5, void *a6, void *a7, void *a8)
{
        audit_token_t *callerToken = (audit_token_t *)a1;
        if (!cloak_caller_is_platform(callerToken)) return -2;

        const char *mountPoint = (const char *)a2;
        const char *error = (const char *)a3;

        if (mountPoint) {
                strlcpy(gCloakMountPoint, mountPoint, sizeof(gCloakMountPoint));
                gCloakMountActive = true;
        }
        else {
                gCloakMountPoint[0] = '\0';
                gCloakMountActive = false;
        }

        if (error) {
                strlcpy(gCloakLastError, error, sizeof(gCloakLastError));
        }
        else {
                gCloakLastError[0] = '\0';
        }

        return 0;
}

struct jbserver_domain gCloakDomain = {
        .permissionHandler = NULL, // GET_POLICY is systemwide; mutations check per-action
        .actions = (struct jbserver_action[]){
                // JBS_CLOAK_GET_POLICY
                {
                        .handler = cloak_get_policy,
                        .args = (jbserver_arg[]){
                                { .name = "enabled",          .type = JBS_TYPE_BOOL,   .out = true },
                                { .name = "hideMounts",       .type = JBS_TYPE_BOOL,   .out = true },
                                { .name = "hideCredentials",  .type = JBS_TYPE_BOOL,   .out = true },
                                { .name = "hideTrustcache",   .type = JBS_TYPE_BOOL,   .out = true },
                                { .name = "stealthLevel",     .type = JBS_TYPE_UINT64, .out = true },
                                // R40 注：blacklistMode 不入本表——jbserver 框架限 8 参且本表已满，
                                // 插入会导致处理器错位+error 出参截断。读路径统一走 jbsettings 域
                                // cloakBlacklistMode 键（set_options 的入参写入侧保留在此域）。
                                { .name = "mountActive",      .type = JBS_TYPE_BOOL,   .out = true },
                                { .name = "mountPoint",       .type = JBS_TYPE_STRING, .out = true },
                                { .name = "error",            .type = JBS_TYPE_STRING, .out = true },
                                { 0 },
                        },
                },
                // JBS_CLOAK_ENABLE
                {
                        .handler = cloak_enable,
                        .args = (jbserver_arg[]){
                                { .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
                                { 0 },
                        },
                },
                // JBS_CLOAK_DISABLE
                {
                        .handler = cloak_disable,
                        .args = (jbserver_arg[]){
                                { .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
                                { 0 },
                        },
                },
                // JBS_CLOAK_SET_OPTIONS
                {
                        .handler = cloak_set_options,
                        .args = (jbserver_arg[]){
                                { .name = "caller-token",     .type = JBS_TYPE_CALLER_TOKEN, .out = false },
                                { .name = "hideMounts",       .type = JBS_TYPE_BOOL,         .out = false },
                                { .name = "hideCredentials",  .type = JBS_TYPE_BOOL,         .out = false },
                                { .name = "hideTrustcache",   .type = JBS_TYPE_BOOL,         .out = false },
                                { .name = "stealthLevel",     .type = JBS_TYPE_UINT64,       .out = false },
                                { .name = "blacklistMode",    .type = JBS_TYPE_BOOL,         .out = false }, // R40
                                { 0 },
                        },
                },
                // JBS_CLOAK_MOUNT_REPORT
                {
                        .handler = cloak_mount_report,
                        .args = (jbserver_arg[]){
                                { .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
                                { .name = "mountPoint",   .type = JBS_TYPE_STRING,       .out = false },
                                { .name = "error",        .type = JBS_TYPE_STRING,       .out = false },
                                { 0 },
                        },
                },
                { 0 },
        },
};


/* ---------------------------------------------------------------------------
 * R38/S2 TODO（用户 2026-08-29 11:41 双形态 + C R46 向量清单检查项）：
 * 未注入进程的 csops 呈现。systemhook 的 csops_hook 只保护"被注入进程"；
 * data-only 链（ucred patch+签名翻转，A 11:47）翻转后，未注入子进程可能
 * 带着翻转后的 csflags 直接查询（CS_GET_TASK_ALLOW 等位无遮蔽）。
 * 深档（rootful 态）的完整闭环需要本层（launchdhook/系统级）全局过滤——
 * S2 执行层重写时随 Form-B 六面向量一并落（B 认领，见 CHANGES §8.11/8.12）。
 * ------------------------------------------------------------------------ */
