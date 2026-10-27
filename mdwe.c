// mdwe.c: sleeps forever; with any argument it first turns on memory-deny-write-execute, as a
// bun --compile --aot executable does at startup. Shows CRIU's failure needs only MDWE, not Bun.
#include <stdio.h>
#include <sys/prctl.h>
#include <unistd.h>

#ifndef PR_SET_MDWE
#define PR_SET_MDWE 65
#define PR_MDWE_REFUSE_EXEC_GAIN 1
#endif

int main(int argc, char **argv) {
  if (argc > 1 && prctl(PR_SET_MDWE, PR_MDWE_REFUSE_EXEC_GAIN, 0, 0, 0)) {
    perror("prctl(PR_SET_MDWE)");
    return 1;
  }
  for (;;) pause();
}
