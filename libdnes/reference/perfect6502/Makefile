OBJS=perfect6502.o
OBJS+=measure.o
#CFLAGS=-Wall -ggdb -O0
CFLGAS=-O3 -
CC=clang

all: measure

measure: $(OBJS)
	$(CC) -o measure $(OBJS)

clean:
	rm -f $(OBJS) measure

