#!/bin/sh
set -eu

usage()
{
	echo "usage: $0 <mach-o-binary> [architecture] [minimum-ios-version]" >&2
	exit 2
}

test "$#" -ge 1 && test "$#" -le 3 || usage

binary=$1
expected_arch=${2:-arm64e}
expected_minos=${3:-}

test -f "$binary" || {
	echo "error: binary not found: $binary" >&2
	exit 1
}

for required_tool in file lipo otool codesign xcrun grep awk; do
	command -v "$required_tool" >/dev/null 2>&1 || {
		echo "error: required tool not found: $required_tool" >&2
		exit 1
	}
done

file_output=$(file "$binary")
case "$file_output" in
	*"Mach-O"*) ;;
	*)
		echo "error: not a Mach-O binary: $file_output" >&2
		exit 1
		;;
esac

architectures=$(lipo -archs "$binary")
case " $architectures " in
	*" $expected_arch "*) ;;
	*)
		echo "error: expected architecture $expected_arch; found: $architectures" >&2
		exit 1
		;;
esac

build_output=$(xcrun vtool -show-build "$binary")
echo "$build_output" | grep -Eq '^[[:space:]]*platform IOS$' || {
	echo "error: Mach-O build platform is not IOS" >&2
	echo "$build_output" >&2
	exit 1
}

if test -n "$expected_minos"; then
	echo "$build_output" |
		awk -v expected="$expected_minos" '
			$1 == "minos" && $2 == expected { found = 1 }
			END { exit(found ? 0 : 1) }
		' || {
			echo "error: minimum iOS version is not $expected_minos" >&2
			echo "$build_output" >&2
			exit 1
		}
fi

codesign --verify --strict --verbose=2 "$binary"

echo "Binary: $binary"
echo "File: $file_output"
echo "Architectures: $architectures"
echo "Build:"
echo "$build_output" | awk '
	$1 == "platform" || $1 == "minos" || $1 == "sdk" {
		print "  " $1 " " $2
	}
'
echo "Dependencies:"
otool -L "$binary" | awk 'NR > 1 { print "  " $1 }'
echo "Signature: valid"
