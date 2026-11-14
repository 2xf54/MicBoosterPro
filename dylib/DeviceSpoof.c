#include <string.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include "fishhook.h"

#define SPOOFED_MACHINE "Unknown"

static int (*orig_uname)(struct utsname *) = NULL;
static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t) = NULL;

static int hooked_uname(struct utsname *name) {
    int ret = orig_uname ? orig_uname(name) : -1;
    if (ret == 0 && name != NULL) {
        strlcpy(name->machine, SPOOFED_MACHINE, sizeof(name->machine));
    }
    return ret;
}

static int hooked_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name != NULL && (strcmp(name, "hw.machine") == 0 || strcmp(name, "hw.model") == 0)) {
        size_t spoof_len = sizeof(SPOOFED_MACHINE); // includes NUL terminator
        if (oldp == NULL) {
            if (oldlenp != NULL) {
                *oldlenp = spoof_len;
            }
            return 0;
        }
        if (oldlenp != NULL) {
            size_t copy_len = *oldlenp < spoof_len ? *oldlenp : spoof_len;
            memcpy(oldp, SPOOFED_MACHINE, copy_len);
            if (copy_len > 0) {
                ((char *)oldp)[copy_len - 1] = '\0';
            }
            *oldlenp = spoof_len;
            return 0;
        }
    }
    return orig_sysctlbyname ? orig_sysctlbyname(name, oldp, oldlenp, newp, newlen) : -1;
}

__attribute__((constructor))
static void init_device_spoof(void) {
    struct rebinding rebindings[] = {
        { "uname", (void *)hooked_uname, (void **)&orig_uname },
        { "sysctlbyname", (void *)hooked_sysctlbyname, (void **)&orig_sysctlbyname }
    };
    rebind_symbols(rebindings, 2);
}
