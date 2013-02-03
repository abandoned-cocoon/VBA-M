#include <cstdio>
#include "../gba/GBA.h"
#include "../gba/Sound.h"
#include "../common/Port.h"

#define debuggerReadMemory(addr) \
  (*(u32*)&map[(addr)>>24].address[(addr) & map[(addr)>>24].mask])

#define debuggerReadHalfWord(addr) \
  (*(u16*)&map[(addr)>>24].address[(addr) & map[(addr)>>24].mask])

#define debuggerReadByte(addr) \
  map[(addr)>>24].address[(addr) & map[(addr)>>24].mask]

#define debuggerWriteMemory(addr, value) \
  *(u32*)&map[(addr)>>24].address[(addr) & map[(addr)>>24].mask] = (value)

#define debuggerWriteHalfWord(addr, value) \
  *(u16*)&map[(addr)>>24].address[(addr) & map[(addr)>>24].mask] = (value)

#define debuggerWriteByte(addr, value) \
  map[(addr)>>24].address[(addr) & map[(addr)>>24].mask] = (value)

extern bool debugger;
extern struct EmulatedSystem emulator;

// void luaMain();
// void luaSignal(int,int);
// void luaOutput(const char *, u32);

void luaMain() {
    if(emulator.emuUpdateCPSR)
        emulator.emuUpdateCPSR();

    //debuggerRegisters(0, NULL);

    while(debugger) {
        soundPause();
        // debuggerDisableBreakpoints();
        puts("debugger> TODO");
        debugger = false;
    }
}

void luaSignal(int sig, int number) {
    if (sig != 5) {
        printf("Dear developer who added a new signal-type (%d) to this emulator,\n", sig);
        printf("please update luactrl.cpp. Thank you.\n");
        return;
    }
    printf("Breakpoint %d reached\n", number);

    //debuggerDisableBreakpoints();
    //debuggerPrefetch();
    //emulator.emuMain(1);
    //debuggerEnableBreakpoints(false);
    return;

/*    bool cond = debuggerCondEvaluate(number & 255);
    debugger = true;
    debuggerAtBreakpoint = true;
    debuggerBreakpointNumber = number;
    debuggerDisableBreakpoints();*/
}

void luaOutput(const char *s, u32 addr) {
    char c;
    if (s) puts(s);
    if (addr) while(c = debuggerReadByte(addr++))
        putchar(c);
    puts("");
}

