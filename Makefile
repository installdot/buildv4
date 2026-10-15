# Not a Theos project. TempMailTrace.mm has no %hook directives and does not link Substrate.
.PHONY: all clean
all:
	sh build.sh

clean:
	rm -rf build
