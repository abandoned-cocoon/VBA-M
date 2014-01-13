#include <cstdio>
#include <cstring>

extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

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
        lua_pushstring(L, "reg(x, [value]): needs at least one argument");

    } else if (!lua_isnumber(L, 1) || (r = lua_tonumber(L, 1)) >= 16) {
        lua_pushstring(L, "reg(x): x has to be a number between 0 and 15");

    } else if (argc == 2 && !lua_isnumber(L, 2)) {
        lua_pushstring(L, "reg(x, value): value has to be a number");

    } else if (argc > 2) {
        lua_pushstring(L, "reg(x, [value]): too many arguments");

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
        lua_pushstring(L, "mem(x, [value]): needs at least one argument");

    } else if (!lua_isnumber(L, 1)) {
        lua_pushstring(L, "mem(x): x has to be a number");

    } else if (argc == 2 && !lua_isnumber(L, 2)) {
        lua_pushstring(L, "mem(x, value): value has to be a number");

    } else if (argc > 2) {
        lua_pushstring(L, "mem(x, [value]): too many arguments");

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

int ip(lua_State *L) {
    if (lua_gettop(L) != 0) {
        lua_pushstring(L, "ip(): takes no arguments");
        return lua_error(L);
    }

    lua_pushinteger(L, reg[15].I - (armState?4:2));
    return 1;
}

struct DebuggerCommand {
  const char *name;
  void (*function)(int,char **);
  const char *help;
  const char *syntax;
};

extern DebuggerCommand debuggerCommands[];

int oldapi(lua_State *L) {
    unsigned int argc = lua_gettop(L);

    if (argc == 0) {
        lua_pushstring(L, "oldapi(name, ...): needs at least one argument");
        return lua_error(L);
    }

    const char *first = lua_tostring(L, 1);
    char **args = new char*[argc];

    int i;
    for (i=0; i<argc; i++) {
        args[i] = (char*) lua_tostring(L, i+1);
    }


    for (i=0; ; i++) {
        if (!debuggerCommands[i].name) {
            lua_pushstring(L, "legacy command not found");
            return lua_error(L);
        }
        if (strcmp(debuggerCommands[i].name, first) == 0) break;
    }

    debuggerCommands[i].function(argc, args);
    delete[] args;
}

extern u32 cpuPrefetch[2];

void prefetch() {

    if(armState) {
        cpuPrefetch[0] = memory<u32>(armNextPC);
        cpuPrefetch[1] = memory<u32>(armNextPC+4);

    } else {
        cpuPrefetch[0] = memory<u16>(armNextPC);
        cpuPrefetch[1] = memory<u16>(armNextPC+2);

    }
}

int emulate(lua_State *L) {
    if (lua_gettop(L) != 1) {
        lua_pushstring(L, "emulate(steps): needs exactly one argument");

    } else if (!lua_isnumber(L, 1)) {
        lua_pushstring(L, "emulate(steps): steps has to be a number");

    } else {
        prefetch();
        emulator.emuMain(lua_tonumber(L, 1));
        return 0;

    }
    return lua_error(L);

}

lua_State *L;

void luaInit() {
    L = lua_open();
    lua_gc(L, LUA_GCSTOP, 0);  /* stop collector during initialization */
    luaL_openlibs(L);  /* open libraries */
    lua_gc(L, LUA_GCRESTART, 0);

    #define addfunction(name, func) \
        lua_pushcfunction(L, func); \
        lua_setfield(L, -2, name);

    lua_createtable(L, 0, 2);
    addfunction("ip",      &(ip));
    addfunction("oldapi",  &(oldapi));
    addfunction("emulate", &(emulate));
    addfunction("reg",     &(regaccess));
    addfunction("mem32",   &(memaccess<u32>));
    addfunction("mem16",   &(memaccess<u16>));
    addfunction("mem8",    &(memaccess<u8>));
    lua_setglobal(L, "gba");

    #define PATH_PREPEND(n, p) n"=\""p";\".."n";"
    luaL_dostring(L,
        PATH_PREPEND("package.path", "./src/lua-repl/?.lua;./src/lua-repl/?/init.lua")
        PATH_PREPEND("package.cpath", "./src/lua-linenoise/?.so")
    );
    #define TRY(s) {int status = luaL_dostring(L, s); if (status != LUA_OK) report(L, status);}
    TRY(
        "repl = require 'repl.console'\n"
        "require 'linenoise'\n"
        "repl:loadplugin 'linenoise'\n"
        "repl:loadplugin 'history'\n"
        "repl:loadplugin 'completion'\n"
        "repl:loadplugin 'autoreturn'\n"
        "repl:loadplugin 'rcfile'\n"
    )
}

void luaQuit() {
    lua_close(L);
}

void luaMain() {
    if(emulator.emuUpdateCPSR)
        emulator.emuUpdateCPSR();

    // soundPause();
    // dofile(L, "pause.lua");

    puts("");
    puts("Try 'gba.reg(15)' and 'gba.mem16(0x08000000)'. Assign with 'gba.reg(3, 0xAABBCCDD)'.");
    puts("Breakpoints are implemented in 'bkpt.lua'. Load with 'require \"bkpt\"'.");
    puts("For more info read the sourcefile 'luactrl.cpp'. Ctrl+D to resume emulation.");
        TRY("repl:run()")
    debugger = false;
    prefetch();
}

void callback(const char *name, unsigned int args) {
    lua_getglobal(L, name);
    if (lua_isnil(L, -1)) {
        // We're kind of stuck, when that happens.
        // Drop to REPL to let user fix the issue
        lua_pop(L, args+1);
        debugger = true;

    } else {
        if (args) lua_insert(L, -args-1);
        report(L, docall(L, args, 0));
        debugger = false;
    }
}

void luaSignal(int sig, int number) {
    if (sig != 5) {
        printf("Dear developer who added a new signal-type (%d) to this emulator,\n", sig);
        printf("please update luactrl.cpp. Thank you.\n");
        return;
    }
    callback("breakpoint_cb", 0);
}

void luaOutput(const char *s, u32 addr) {
    char c;
    if (s) puts(s);
    if (addr) while((c = memory<u8>(addr++)))
        putchar(c);
    puts("");
}

void debuggerBreakOnWrite(u32 address, u32 oldvalue, u32 value, int size, int t) {
    lua_pushnumber(L, address);
    lua_pushnumber(L, oldvalue);
    lua_pushnumber(L, value);
    lua_pushnumber(L, size);
    callback("watchpoint_cb", 4);
}

