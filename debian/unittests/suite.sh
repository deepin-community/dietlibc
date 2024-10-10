#!/bin/sh

if [ -z "$1" ] || ! [ -d "bin-$1" ]; then
	echo "Usage: $0 DIETARCH" >&2
	exit 1
fi
DIET="bin-$1/diet"

TESTS="
debian/unittests/tc523086.c
debian/unittests/t-ascii1.c
debian/unittests/signal.c
debian/unittests/gettimeofday.c
debian/unittests/strerror.c
debian/unittests/stat.c
debian/unittests/atexit.c
debian/unittests/fopen.c
debian/unittests/socketfns.c
debian/unittests/pselect.c
test/alarm.c
test/bsearch.c
test/byteswap.c
test/dirname.c
test/fadvise.c
test/getenv.c
test/hasmntopt.c
test/iconv.c
test/ltostr.c
test/md5_testharness.c
test/memccpy.c
test/memchr.c
test/memcmp.c
test/memcpy.c
test/memrchr.c
test/mmap_test.c
test/pipe.c
test/printf.c
test/printf2.c
test/putenv.c
test/regex.c
test/select.c
test/sprintf.c
test/sscanf.c
test/stdarg.c
test/strcasecmp.c
test/strchr.c
test/strncat.c
test/strncpy.c
test/strrchr.c
test/strstr.c
test/strtol.c
test/test-newfnmatch.c
test/ungetc.c
test/utime.c
test/waitpid.c
test/dirent/opendir-tst1.c
test/dirent/tst-seekdir.c
test/stdlib/testrand.c
test/stdlib/tst-calloc.c
test/stdlib/tst-system.c
"

# Figure out longest len so we can pretty-print the test results.
LONGEST_LEN=0
for i in $TESTS; do
	if [ ${#i} -gt $LONGEST_LEN ]; then
		LONGEST_LEN=${#i}
 	fi
done

# Figure out if we are running in a Qemu user instance
# (in order to ignore failures from tests that we expect
# will fail under Qemu)
if [ -d /proc/$$ ] ; then
	case $(readlink -f /proc/$$/exe) in
	(*/qemu-*)	QEMU=1 ;;
	(*)		QEMU=0 ;;
	esac
else
	# We should really have /proc during build, but just in
	# case: don't assume Qemu to be on the safe side
	QEMU=0
fi

EXPECT_FAIL=""
NO_STACK_PROTECTOR=""
HOST_ARCH=$(dpkg-architecture -qDEB_HOST_ARCH)
if test 1 = $QEMU; then
	# fadvise is possibly broken on 32bit BE mips, and 32bit PowerPC Qemu
	#   (syscall also fails with glibc, as of Qemu 2.5)
	# printf tests are broken plain powerpc32 (but not powerpcspe), because
	# we compile dietlibc with -mpowerpc-gpopt, but Qemu doesn't emulate the
	# FPU instructions required for that to work (as of Qemu 2.5)
	case $HOST_ARCH in
	(mips|powerpcspe)
		EXPECT_FAIL="test/fadvise.c"
		;;
	(powerpc)
		EXPECT_FAIL="test/fadvise.c test/printf.c test/printf2.c test/sprintf.c"
		;;
	(*)
		;;
	esac
	# many Linux filesystems (in particular ext2/3/4 but not SGI xfs or
	# tmpfs) have too wide dirent offsets for ILP32 nōn-largefile code,
	# possibly excepting actual 32-bit programs; qemu-user is generally
	# 64-bit and therefore cannot provide working telldir at all; see:
	# https://sourceware.org/bugzilla/show_bug.cgi?id=23960
	case $(dpkg-architecture -qDEB_HOST_ARCH_BITS) in
	(32)
		EXPECT_FAIL="$EXPECT_FAIL test/dirent/tst-seekdir.c"
		;;
	esac
fi
case $HOST_ARCH in
(*)
	;;
esac

expect_fail()
{
	for _XF in ${EXPECT_FAIL} ; do
		if [ x"$1" = x"${_XF}" ] ; then
			return 0
		fi
	done
	return 1
}

no_ssp()
{
	for _NS in ${NO_STACK_PROTECTOR} ; do
		if [ x"$1" = x"${_NS}" ] ; then
			return 0
		fi
	done
	return 1
}

HAD_ERROR=0

for variant in bare pthreads ; do
	LDLIBS=""
	if [ "$variant" = "pthreads" ] ; then
		LDLIBS=-lpthread
	fi

	echo "Running dietlibc unittests (variant: $variant):"
	for testname in $TESTS ; do
		# Skip tests that are commented out
		if [ x"${testname###}" != x"${testname}" ] ; then
			continue
		fi
		printf "  %-*s: build: " $LONGEST_LEN $testname
		if no_ssp $testname ; then
			$DIET -v -Os gcc -nostdinc -fno-stack-protector -static -o debian/unittests/ttt $testname $LDLIBS >debian/unittests/gcc.out 2>&1
		else
			$DIET -v -Os gcc -nostdinc -fstack-protector-strong -static -o debian/unittests/ttt $testname $LDLIBS >debian/unittests/gcc.out 2>&1
		fi
		RC=$?
		if [ $RC -ne 0 ] ; then
			printf "ERROR\n"
			{
				echo
				echo "BUILD ERROR for $testname in variant $variant (rc = $RC), gcc output is:"
				echo "------------------------------------------------------------"
				cat debian/unittests/gcc.out
				echo "------------------------------------------------------------"
				echo
			} >> debian/unittests/all_failures.out
			rm -f debian/unittests/gcc.out debian/unittests/ttt
			HAD_ERROR=1
			continue
		fi
		printf "OK    run: "
		rm -f debian/unittests/gcc.out
		debian/unittests/ttt >debian/unittests/run.out 2>&1
		RC=$?
		if [ $RC -ne 0 ] ; then
			printf "ERROR\n"
			{
				echo
				echo "RUN ERROR for $testname in variant $variant (rc = $RC), test output is:"
				echo "------------------------------------------------------------"
				cat debian/unittests/run.out
				echo "------------------------------------------------------------"
				echo
			} >> debian/unittests/all_failures.out
			rm -f debian/unittests/run.out debian/unittests/ttt
			if expect_fail $testname ; then
				echo "> Test was expected to fail, ignoring."
			else
				HAD_ERROR=1
			fi
			continue
		fi
		rm -f debian/unittests/run.out debian/unittests/ttt
		printf "OK\n"
	done
done

if [ -f debian/unittests/all_failures.out ] ; then
	cat debian/unittests/all_failures.out
	rm -f debian/unittests/all_failures.out
fi

exit $HAD_ERROR
