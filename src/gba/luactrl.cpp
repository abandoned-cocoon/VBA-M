#include <cstdio>

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#include "../gba/GBA.h"
#include "../gba/Sound.h"
#include "../common/Port.h"

template <class T>
T& memory (u32 addr) {
    memoryMap& m = map[addr >> 24];
    return *(T*)&m.address[addr & m.mask];
};

extern bool debugger;
extern struct EmulatedSystem emulator;

// void luaMain();
// void luaSignal(int,int);
// void luaOutput(const char *, u32);

#define LUA_OK 0 // defined in lua 5.2

static void l_message (const char *pname, const char *msg) {
  if (pname) fprintf(stderr, "%s: ", pname);
  fprintf(stderr, "%s\n", msg);
  fflush(stderr);
}

static int report (lua_State *L, int status) {
  if (status != LUA_OK && !lua_isnil(L, -1)) {
    const char *msg = lua_tostring(L, -1);
    if (msg == NULL) msg = "(error object is not a string)";
    l_message("vbam-luactrl", msg);
    lua_pop(L, 1);
    /* force a complete garbage collection in case of errors */
    lua_gc(L, LUA_GCCOLLECT, 0);
  }
  return status;
}

static int traceback (lua_State *L) {

#if 0 // 5.2 code; not luajit compatible

  const char *msg = lua_tostring(L, 1);
  if (msg)
    luaL_traceback(L, L, msg, 1);
  else if (!lua_isnoneornil(L, 1)) {  /* is there an error object? */
    if (!luaL_callmeta(L, 1, "__tostring"))  /* try its 'tostring' metamethod */
      lua_pushliteral(L, "(no error message)");
  }
  return 1;
}

#else

  if (!lua_isstring(L, 1))  /* 'message' not a string? */
    return 1;  /* keep it intact */
  lua_getfield(L, LUA_GLOBALSINDEX, "debug");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    return 1;
  }
  lua_getfield(L, -1, "traceback");
  if (!lua_isfunction(L, -1)) {
    lua_pop(L, 2);
    return 1;
  }
  lua_pushvalue(L, 1);  /* pass error message */
  lua_pushinteger(L, 2);  /* skip this function and traceback */
  lua_call(L, 2, 1);  /* call debug.traceback */
  return 1;

#endif

}

static int docall (lua_State *L, int narg, int nres) {
  int status;
  int base = lua_gettop(L) - narg;  /* function index */
  lua_pushcfunction(L, traceback);  /* push traceback function */
  lua_insert(L, base);  /* put it under chunk and args */
  // signal(SIGINT, laction);
  status = lua_pcall(L, narg, nres, base);
  // signal(SIGINT, SIG_DFL);
  lua_remove(L, base);  /* remove traceback function */
  return status;
}

static int dofile (lua_State *L, const char *name) {
  int status = luaL_loadfile(L, name);
  if (status == LUA_OK) status = docall(L, 0, 0);
  return report(L, status);
}

int regaccess(lua_State *L) {
    unsigned int argc = lua_gettop(L), r;

    if (argc == 0) {
        lua_pushstring(L, "reg(n, [value]): needs at least one argument");

    } else if (!lua_isnumber(L, 1) || (r = lua_tonumber(L, 1)) >= 16) {
        lua_pushstring(L, "reg(x): x has to be a number between 0 and 15");

    } else if (argc == 2 && !lua_isnumber(L, 2)) {
        lua_pushstring(L, "reg(x, value): value has to be a number");

    } else if (argc > 2) {
        lua_pushstring(L, "reg(n, [value]): too many arguments");

    } else {
        if (argc == 1) {
            lua_pushnumber(L, reg[r].I);
            return 1;

        } else if (argc == 2) {
            reg[r].I = lua_tonumber(L, 2);
            return 0;

        }   
    }
    return lua_error(L);

}

template <class T>
int memaccess(lua_State *L) {
    unsigned int argc = lua_gettop(L);

    if (argc == 0) {
        lua_pushstring(L, "mem(n, [value]): needs at least one argument");

    } else if (!lua_isnumber(L, 1)) {
        lua_pushstring(L, "mem(x): x has to be a number");

    } else if (argc == 2 && !lua_isnumber(L, 2)) {
        lua_pushstring(L, "mem(x, value): value has to be a number");

    } else if (argc > 2) {
        lua_pushstring(L, "mem(n, [value]): too many arguments");

    } else {
        unsigned int loc = lua_tonumber(L, 1);

        if (argc == 1) {
            lua_pushnumber(L, memory<T>(loc));
            return 1;

        } else if (argc == 2) {
            memory<T>(loc) = lua_tonumber(L, 2);
            return 0;

        }   
    }
    return lua_error(L);

}

void push_cpu_object(lua_State *L) {
    #define addfunction(name, func) \
        lua_pushcfunction(L, func); \
        lua_setfield(L, -2, name);

    lua_createtable(L, 0, 2);
    addfunction("reg",   &(regaccess));
    addfunction("mem32", &(memaccess<u32>));
    addfunction("mem16", &(memaccess<u16>));
    addfunction("mem8",  &(memaccess<u8>));
}

void luaMain() {
    if(emulator.emuUpdateCPSR)
        emulator.emuUpdateCPSR();

    //debuggerRegisters(0, NULL);
    while(debugger) {
        soundPause();
        // debuggerDisableBreakpoints();
        debugger = false;
    }

    lua_State *L = lua_open();
    lua_gc(L, LUA_GCSTOP, 0);  /* stop collector during initialization */
    luaL_openlibs(L);  /* open libraries */
    lua_gc(L, LUA_GCRESTART, 0);

    push_cpu_object(L);
    lua_setglobal(L, "cpu");

    printf("\nTry 'cpu.reg(15)' and 'cpu.mem16(0x08000000)'. Pass a second argument to assign. Ctrl+D to resume emulation.\n");
    #define PATH_PREPEND(n, p) n"=\""p";\".."n";"
    luaL_dostring(L,
        PATH_PREPEND("package.path", "./src/lua-repl/?.lua;./src/lua-repl/?/init.lua")
        PATH_PREPEND("package.cpath", "./src/lua-repl/?.so")
    );
    dofile(L, "src/lua-repl/rep.lua");
    lua_close(L);
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
    if (addr) while((c = memory<u32>(addr++)))
        putchar(c);
    puts("");
}

