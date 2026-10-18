#include <sys/stat.h>
#include <stddef.h>
_Static_assert(sizeof(struct stat)==128,"size");
_Static_assert(_Alignof(struct stat)==8,"align");
_Static_assert(offsetof(struct stat,st_dev)==0,"dev");
_Static_assert(offsetof(struct stat,st_ino)==8,"ino");
_Static_assert(offsetof(struct stat,st_mode)==16,"mode");
_Static_assert(offsetof(struct stat,st_nlink)==20,"nlink");
