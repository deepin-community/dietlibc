#include <stdio.h>

static volatile int i;

int main(int argc, char *argv[]) {
	int j, k;

	i = 1;
	j = 2;
	k = 3;
	__asm__ __volatile__("swp	%0, %1, [%2]"
	    : "+&r" (k)
	    : "r" (j), "r" (&i)
	    : "memory");
	if (i != 2 || j != 2 || k != 1) {
		fprintf(stderr, "E: i=%d j=%d k=%d\n", i, j, k);
		return (1);
	}
	return (0);
}
