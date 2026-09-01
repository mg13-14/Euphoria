#include "jbserver_global.h"
#include "jbsettings.h"

#include <libjailbreak/codesign.h>
#include <libjailbreak/libjailbreak.h>
#include <libproc.h>
#include <unistd.h>

static char *read_file_to_string(const char *path) {
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        return NULL;
    }

    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return NULL;
    }
    long size = ftell(fp);
    if (size < 0) {
        fclose(fp);
        return NULL;
    }
    rewind(fp);

    char *buffer = malloc((size_t)size + 1);
    if (!buffer) {
        fclose(fp);
        return NULL;
    }

    size_t read_bytes = fread(buffer, 1, (size_t)size, fp);
    fclose(fp);

    if (read_bytes != (size_t)size) {
        free(buffer);
        return NULL;
    }

    buffer[size] = '\0';
    return buffer;
}


bool euphoria_domain_allowed(audit_token_t clientToken)
{
        char path[PATH_MAX];
        if (proc_pidpath_audittoken(&clientToken, path, PATH_MAX) <= 0) return false;
        return is_euphoria_app(path);
}

bool euphoria_is_jailbroken(char **outVersion)
{
        // R34（用户 00:19 实锤修复："卡住→退出显示已越狱"假状态机）：
        // 原实现无条件 return true——launchdhook 一注入就算"越狱成功"，
        // 后续 bootstrap/包管理/隐藏装一半卡死，重启 App 依旧显示"已越狱"。
        // 改为事务式：只有 daemon 全流程（bootstrap→守护进程→rootful/cloak）
        // 走完并写出 .bootstrap_complete 标记后才算已越狱；半程状态=未越狱，
        // 用户可直接重点越狱按钮幂等重跑（finalize_bootstrap_if_needed 幂等）。
        char *version = read_file_to_string(JBROOT_PATH("/basebin/.version"));
        if (!version) {
                *outVersion = NULL;
                return false;
        }
        if (access(JBROOT_PATH("/basebin/.bootstrap_complete"), F_OK) != 0) {
                free(version);
                *outVersion = NULL;
                return false;
        }
        *outVersion = version;
        return true;
}

int euphoria_get_root(audit_token_t *processToken)
{
        pid_t pid = audit_token_to_pid(*processToken);
        uint64_t proc = proc_find(pid);
        uint64_t ucred = proc_ucred(proc);

        if (kread32(ucred + koffsetof(ucred, uid)) == 501) {
                kwrite32(ucred + koffsetof(ucred, uid), 0);
                kwrite32(ucred + koffsetof(ucred, groups), 0);

                if (gSystemInfo.kernelStruct.proc_ro.exists) {
                        uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));

                        if (koffsetof(proc_ro, task_tokens)) {
                                uint64_t auditToken = proc_ro + koffsetof(proc_ro, task_tokens) + koffsetof(task_token_ro_data, audit_token);
                                kwrite32(auditToken + 4, 0); // uid
                                kwrite32(auditToken + 8, 0); // gid
                        }
                }

                return 0;
        }

        return 1;
}

int euphoria_drop_root(audit_token_t *processToken)
{
        pid_t pid = audit_token_to_pid(*processToken);
        uint64_t proc = proc_find(pid);
        uint64_t ucred = proc_ucred(proc);

        if (kread32(ucred + koffsetof(ucred, uid)) == 0) {
                kwrite32(ucred + koffsetof(ucred, uid), 501);
                kwrite32(ucred + koffsetof(ucred, groups), 501);

                if (gSystemInfo.kernelStruct.proc_ro.exists) {
                        uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));

                        if (koffsetof(proc_ro, task_tokens)) {
                                uint64_t auditToken = proc_ro + koffsetof(proc_ro, task_tokens) + koffsetof(task_token_ro_data, audit_token);
                                kwrite32(auditToken + 4, 501); // uid
                                kwrite32(auditToken + 8, 501); // gid
                        }
                }

                return 0;
        }

        return 1;
}

struct jbserver_domain gEuphoriaDomain = {
        .permissionHandler = euphoria_domain_allowed,
        .actions = {
                // JBS_EUPHORIA_IS_JAILBROKEN
                {
                        .handler = euphoria_is_jailbroken,
                        .args = (jbserver_arg[]){
                                { .name = "version", .type = JBS_TYPE_STRING, .out = true },
                                { 0 },
                        },
                },
                // JBS_EUPHORIA_GET_ROOT
                {
                        .handler = euphoria_get_root,
                        .args = (jbserver_arg[]){
                                { .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
                                { 0 },
                        },
                },
                // JBS_EUPHORIA_DROP_ROOT
                {
                        .handler = euphoria_drop_root,
                        .args = (jbserver_arg[]){
                                { .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
                                { 0 },
                        },
                },
                { 0 },
        },
};