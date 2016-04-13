OBJS=perfect6502.o
OBJS+=measure.o
#CFLAGS=-Wall -ggdb -O0
CFLAGS=-O0 -std=c11
CC=gcc#clang

all: measure

measure: $(OBJS)
	$(CC) -o measure $(OBJS)

clean:
	rm -f $(OBJS) measure

