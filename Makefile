CC = gcc
CFLAGS = -static
LDFLAGS = -lelf

lz.o: lz.c
	$(CC) $(CFLAGS) -c lz.c

packer.o: packer.c
	$(CC) $(CFLAGS) -c packer.c

packer: lz.o packer.o
	$(CC) $(CFLAGS) -o packer lz.o packer.o $(LDFLAGS) -static

clean:
	rm -f packer lz.o packer.o stub_amd64 stub_i386
