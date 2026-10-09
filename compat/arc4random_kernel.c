/* SpeedBackup static-Bionic compatibility: no userspace random state.
 * getrandom(flags=0) waits for kernel CRNG readiness. Never weaken failures.
 * Linux >= 3.17 provides getrandom; Android legacy kernel 4.9 is supported.
 * Every request is independent across fork and threads, so Bionic's atfork
 * lock hooks intentionally have nothing to lock. Uniform sampling remains
 * the original Bionic rejection-sampling implementation in libc.a.
 */
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/random.h>
#include <unistd.h>
#ifndef SB_GETRANDOM
#define SB_GETRANDOM getrandom
#endif
void arc4random_buf(void *buffer, size_t length) {
    int saved_errno = errno;
    unsigned char *p = (unsigned char *)buffer;
    while (length != 0) {
        size_t chunk = length > 256 ? 256 : length;
        ssize_t n = SB_GETRANDOM(p, chunk, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0 || (size_t)n > chunk) {
            static const char msg[] = "SpeedBackup: kernel random source failed\n";
            (void)write(STDERR_FILENO, msg, sizeof(msg)-1);
            abort();
        }
        p += (size_t)n;
        length -= (size_t)n;
    }
    errno = saved_errno;
}
uint32_t arc4random(void) {
    uint32_t result;
    arc4random_buf(&result, sizeof(result));
    return result;
}
void arc4random_mutex_lock(void) {}
void arc4random_mutex_unlock(void) {}
