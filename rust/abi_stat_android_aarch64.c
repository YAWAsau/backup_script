#include <sys/stat.h>
#include <stddef.h>
#include <sys/vfs.h>
_Static_assert(sizeof(struct statfs)==120,"statfs size");
_Static_assert(offsetof(struct statfs,f_type)==0,"statfs type");
_Static_assert(offsetof(struct statfs,f_flags)==80,"statfs flags");
_Static_assert(sizeof(struct stat)==128,"size");
_Static_assert(_Alignof(struct stat)==8,"align");
_Static_assert(offsetof(struct stat,st_dev)==0,"dev");
_Static_assert(offsetof(struct stat,st_ino)==8,"ino");
_Static_assert(offsetof(struct stat,st_mode)==16,"mode");
_Static_assert(offsetof(struct stat,st_nlink)==20,"nlink");
