TARGET = main
CFLAGS = -arch i686 
LDFLAGS = -framework CoreFoundation -framework MobileDevice -F/System/Library/PrivateFrameworks 

all: $(TARGET)	

%.o::   %.c
	$CC $< 

clean:
	rm -f main
	rm -f *.o

    

        