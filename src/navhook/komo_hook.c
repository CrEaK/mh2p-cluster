/*
 * komo_hook - trial: the phone's turn in the cockpit box and on the head-up
 * display without an Audi route.
 * Copyright (c) 2026 CrEaK (https://github.com/CrEaK). GPL-3.0-or-later.
 *
 * Loaded into Audi's navigation process (navStartup) as a dependency of one of
 * its own libraries: libwatchdog.so in /mnt/app/navigation gets one more
 * DT_NEEDED entry, "dog.so" (add_needed.py; the name is the tail of the
 * library's own soname, its RPATH is $ORIGIN), and this library is installed
 * next to it under that name. navStartup, its name and the way the service
 * manager starts it stay as they are. (A first attempt started navStartup
 * through a wrapper script as navStartup.real: on an A6 C8, 2026-11-26, the
 * navigation did not come up that way, with or without the library.)
 *
 * Does nothing unless the switch file is there, and hooks nothing unless the
 * build of navStartup is one it was written for: MH2p P2711
 * (MIB2P_MAIN_19_39_5, 47516812 bytes) or P2873 (MIB2P_MAIN_21_26_3,
 * 47923536 bytes), see builds[].
 *
 * Why. The box the cockpit shows at the right while Audi's navigation guides,
 * and the picture on the head-up display, are drawn by one class in
 * navStartup, ce_dev::KomoViewService (one instance per view). Its "follow"
 * scene is an SVG template (assets/olympia/.../follow/follow.svg: flag,
 * arrival, remaining distance, arrow, "in", distance) filled from the pair of
 * RouteInfoElement the HMI sends with DSIKOMOView.setRouteInfo(). The mod's
 * Java class HudTurnFeed already puts the phone's manoeuvre into that pair
 * (seen on an A6 C8, 2026-11-26). But the scene is switched by the
 * navigation's own guidance: without an Audi route the service shows its
 * empty scene, freezes the renderer and reports "not visible".
 *
 * What it does. The class's vtable is exported (_ZTVN6ce_dev15KomoViewServiceE)
 * and lies in the writable data segment (no GNU_RELRO). At load the slots of
 * setRouteInfo are pointed at this library: slot 22 of the primary vtable and
 * slot 43, the thunk of the DSIKOMOView base (this - 4), which is the one the
 * DSI stub calls. Each call runs the original and then looks at
 * /tmp/komo_follow, which HudTurnFeed keeps:
 *
 *   first byte '1'  the phone guides and Audi's navigation does not: show the
 *                   follow scene (show_scene, slot 26, scene type 1), and on
 *                   every later call wake the render engine if it sleeps
 *                   (on_guidance_started, slot 13)
 *   first byte '5'  as '1', with the destination scene (scene type 5) in place
 *                   of the follow scene: the flag picture near the end of the
 *                   phone's route (navhook5, see "The destination scene")
 *   first byte '0'  Audi's navigation guides: hands off, its scenes are its own
 *   a second byte   the same for the head-up display's view alone, the first
 *                   byte then is for the cockpit's view alone (navhook6): "01"
 *                   is the arrow on the head-up display without the box in the
 *                   cockpit, "10" the box without the head-up display. One
 *                   byte is for both, as before. The head-up display's view is
 *                   the one with style variant 5 or 6 (setup_with_style keeps
 *                   the variant at + 176; MOSTHUDKDKHandler asks for 5, 6 or
 *                   255, the cockpit's handler for 1 to 4).
 *   no file         the phone stopped: if the scene was ours, back to the empty
 *                   scene (on_guidance_stopped, slot 14); the renderer then
 *                   reports "not visible" and the cockpit hides the box
 *
 * show_scene takes a ManeuverWithDistance, an object of a library class that
 * cannot be built here. The service keeps one of its own at this + 196;
 * handing that one in makes show_scene skip the copy (it compares the
 * addresses), and FollowModeScene's set-manoeuvre function is empty (vtable
 * slot 14 of _ZTVN6ce_dev15FollowModeSceneE is a bare "bx lr").
 *
 * The render engine (GuidanceViewRenderEngine, the service's member at + 164)
 * draws on demand. A frozen engine ignores "draw again" (set_freeze keeps the
 * flag at + 308; request_render returns when it is set), and the service
 * freezes it whenever a frame of the empty scene is done (on_rendered).
 * switch_scene, which show_scene ends in, freezes, sets the scene and
 * unfreezes by itself. The first version called on_guidance_started (unfreeze)
 * right before show_scene: that woke the render thread while the empty scene
 * was still the current one, and its "empty scene drawn" came in after
 * switch_scene had unfrozen. The follow scene's fade still ran (the redraw was
 * queued already), then the engine slept for good with the frame reported
 * visible: the picture stopped at what it held about a second after the start
 * (A6 C8, second route in a row, 2026-11-27; on a car with a head-up display
 * the arrow there stayed "straight on, no distance", the phone's first data).
 * So show_scene goes alone now, and while the scene is ours each setRouteInfo
 * looks at the engine's flag and wakes it when it is set.
 *
 * The destination scene. show_scene_internal(5) takes the manoeuvre element
 * from the pair that was just stored (3 = destination, which is what CarPlay
 * sends for the arrival), lets the special manoeuvre scene pick its picture
 * and switches to it. Read in both builds before this was added: the scene
 * uses the ManeuverWithDistance only to copy it and to ask whether it is
 * valid (it logs "maneuver.valid=%d"), and the service's questions to it
 * (side of the road, kind of manoeuvre) return an error for an empty one and
 * leave their default, so the picture is "destination on the road". The
 * scene has no distance and no street; the head-up display's handler only
 * logs the change of the view type. Not seen on a car yet.
 *
 * Scene types, from the jump table of show_scene_internal: 0 empty, 1 follow,
 * 2 prepare, 3 action, 4 u-turn, 5 destination, 6 compass, 7 extended follow.
 *
 * Two stages. Without the switch (cluster/komo_hook) the library writes one
 * line to its log and returns: that proves the way it is loaded. With the
 * switch it hooks, behind a safety net: the first start of a boot leaves
 * /tmp/komo_hook_started (/tmp is RAM). A start that finds it is a restart in
 * the same boot, so the navigation died or was restarted: that start stays
 * unhooked and is counted in /mnt/ota/modkit/komo_hook_fails. A start that
 * lasts 60 seconds resets the count; three in a row and the hook stays out
 * until the file is deleted. (A first version kept a file across boots and
 * removed it after 60 seconds; on the car, 2026-11-27, it was still there at
 * the next boot although that start had been good, and the hook stayed out.)
 *
 * Read in the binary of an A6 C8 on P2711 (dumped 2026-11). The first version
 * (navhook2) ran on that car and on a second one with a head-up display on
 * 2026-11-27: box and head-up picture came up, and both showed the freeze
 * described above. The version with the wake-up (navhook3) ran on the A6 the
 * same day: six starts in a row, the box followed each time. P2873 was added
 * from a dump of a third car (navhook4) and has not run on one yet.
 * One line per event goes to /tmp/komo_hook.log.
 */
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#ifndef KOMO_TEST
#define VT_SYMBOL   "_ZTVN6ce_dev15KomoViewServiceE"
#define ENGINE_SYMBOL "_ZTVN6ce_dev24GuidanceViewRenderEngineE"
#define FLAG_FILE   "/tmp/komo_follow"
#define LOG_FILE    "/tmp/komo_hook.log"
#define SWITCH_FILE "/mnt/app/eso/bin/apps/cluster/komo_hook"
#define TRY_FILE    "/mnt/ota/modkit/komo_hook_try"   /* first version's file, only removed now */
#define BOOT_FILE   "/tmp/komo_hook_started"
#define FAILS_FILE  "/mnt/ota/modkit/komo_hook_fails"
#define ALIVE_S     60
#define THUNK_ADJUST 4
#endif
#define MAX_FAILS   3

#define SLOT_ANCHOR       2     /* destructor, the reference for the distances */
#define SLOT_GUIDE_START  13
#define SLOT_GUIDE_STOP   14
#define SLOT_SET_ROUTE    22
#define SLOT_SHOW_SCENE   26
#define SLOT_ROUTE_THUNK  43
#define SCENE_FOLLOW      1
#define SCENE_DESTINATION 5
#define OFF_FRAME_VISIBLE 173   /* set_frame_visible() stores its flag here */
#define OFF_STYLE         176   /* setup_with_style() stores the style variant here */
#define OFF_SCENE_TYPE    188   /* show_scene_internal() stores the scene type it settled on here */
#define OFF_OWN_MANEUVER  196   /* the service's own ManeuverWithDistance */
#define OFF_ENGINE        164   /* the service's render engine */
#define OFF_ENGINE_FROZEN 308   /* GuidanceViewRenderEngine::set_freeze() keeps its flag here */
#define MAX_WAKE_LINES    20    /* per view */
#define RESHOW_MS         2000
#define MAX_RESHOWS       5     /* per guidance: a view whose style has no follow scene never gets visible */
#define MAX_VIEWS         4
#define MAX_LOG_LINES     400

/*
 * The builds of navStartup this was read from. Link addresses (bit 0: Thumb); only their distances
 * count, the process is loaded somewhere else. The five slots are those of slot_index[].
 *
 * P2873 (2026-11-27, dump of a second car): the same code at other addresses. Checked there in the
 * binary: the names of the functions in slots 13, 14, 22, 26 and 34, the thunk in slot 43
 * (sub r0, #4), the offsets 164, 173, 188, 196 and the engine's 308, switch_scene's order (freeze,
 * set-manoeuvre, route infos, set scene, unfreeze), the empty set-manoeuvre of FollowModeScene, the
 * self-assignment check of the manoeuvre, scene type 1 in the jump table. Nobody has run it there.
 */
struct build {
    const char *name;
    uintptr_t vtable;       /* _ZTVN6ce_dev15KomoViewServiceE */
    uintptr_t anchor;       /* its slot 2, the destructor */
    uintptr_t engine;       /* _ZTVN6ce_dev24GuidanceViewRenderEngineE */
    uintptr_t slot[5];
};
static const int slot_index[5] = { SLOT_GUIDE_START, SLOT_GUIDE_STOP, SLOT_SET_ROUTE, SLOT_SHOW_SCENE, SLOT_ROUTE_THUNK };
#ifndef KOMO_TEST
static const struct build builds[] = {
    { "P2711, MIB2P_MAIN_19_39_5", 0x02ca5ca0, 0x813135, 0x02cab0c0,
      { 0x80fcf5, 0x81004d, 0x8117cd, 0x812165, 0x81198d } },
    { "P2873, MIB2P_MAIN_21_26_3", 0x02d092d8, 0x81d131, 0x02d0e748,
      { 0x8188f1, 0x818c49, 0x81be0d, 0x81c8f1, 0x81c0b1 } },
};
static const int n_builds = (int)(sizeof builds / sizeof builds[0]);
/* first bytes of setRouteInfo (stmdb sp!, {r4-r11, lr}) and of its thunk (sub.w r0, r0, #4), the same in both */
static const unsigned char code_set_route[] = { 0x2d, 0xe9, 0xf0, 0x4f };
static const unsigned char code_thunk[]     = { 0xa0, 0xf1, 0x04, 0x00 };
#else
extern struct build builds[];
extern int n_builds;
extern unsigned char code_set_route[4];
extern unsigned char code_thunk[4];
#endif

typedef void (*fn_self)(void *self);
typedef void (*fn_route)(void *self, void *elements);
typedef void (*fn_scene)(void *self, int scene_type, void *maneuver);

struct view {
    void *self;
    int ours;                   /* the scene type we put up (SCENE_FOLLOW, SCENE_DESTINATION), 0 = none */
    int reshows;
    int wakes;
    long shown_ms;
};

static fn_self  guide_start, guide_stop;
static fn_route set_route;
static fn_scene show_scene;
static struct view views[MAX_VIEWS];
static int log_lines;
static int armed;
static uintptr_t engine_vptr;   /* what an engine object of the known class starts with; 0 = not known */

static void say(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void say(const char *fmt, ...)
{
    char line[320];
    int n, fd;
    va_list ap;
    struct timespec ts;

    if (log_lines >= MAX_LOG_LINES) {
        return;
    }
    ++log_lines;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    n = snprintf(line, sizeof line, "%ld s  ", (long)ts.tv_sec);
    va_start(ap, fmt);
    n += vsnprintf(line + n, sizeof line - (size_t)n - 2, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof line - 2) {
        n = (int)sizeof line - 2;
    }
    line[n++] = '\n';
    fd = open(LOG_FILE, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        if (write(fd, line, (size_t)n) < 0) {
            /* nothing to do about it */
        }
        close(fd);
    }
}

static long now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long)ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static int scene_of(char c)
{
    return c == '1' ? SCENE_FOLLOW : c == '5' ? SCENE_DESTINATION : 0;
}

static int is_hud(void *self)
{
    int style = *(int *)((char *)self + OFF_STYLE);
    return style == 5 || style == 6;
}

/* What this view shall show: a scene type (1 follow, 5 destination), 0 hands off, -1 no file. */
static int wanted(void *self)
{
    char c[2] = { 0, 0 };
    int n, fd = open(FLAG_FILE, O_RDONLY);
    if (fd < 0) {
        return -1;
    }
    n = (int)read(fd, c, 2);
    close(fd);
    if (n < 1) {
        return 0;
    }
    /* a second byte that is one of ours is the head-up display's own; anything else (a newline) is none */
    if (n == 2 && (c[1] == '0' || c[1] == '1' || c[1] == '5') && is_hud(self)) {
        return scene_of(c[1]);
    }
    return scene_of(c[0]);
}

static const char *scene_name(int type)
{
    return type == SCENE_DESTINATION ? "destination" : "follow";
}

static struct view *view_of(void *self)
{
    int i;
    for (i = 0; i < MAX_VIEWS; ++i) {
        if (views[i].self == self) {
            return &views[i];
        }
    }
    for (i = 0; i < MAX_VIEWS; ++i) {
        if (views[i].self == NULL) {
            views[i].self = self;
            say("view %d: service at %p, style %d", i, self, *(int *)((char *)self + OFF_STYLE));
            return &views[i];
        }
    }
    return NULL;
}

/* The engine's freeze flag: 1 frozen, 0 not, -1 cannot tell (no engine yet, or not the class this was read from). */
static int frozen(void *self)
{
    void *engine = *(void **)((char *)self + OFF_ENGINE);
    if (engine == NULL || engine_vptr == 0 || *(uintptr_t *)engine != engine_vptr) {
        return -1;
    }
    return *((unsigned char *)engine + OFF_ENGINE_FROZEN) != 0;
}

/* After the original setRouteInfo: self is the KomoViewService itself. */
static void after_route(void *self)
{
    struct view *v = view_of(self);
    int want;
    long now;

    if (v == NULL) {
        return;
    }
    want = wanted(self);
    if (want > 0) {
        int visible = *((unsigned char *)self + OFF_FRAME_VISIBLE) != 0;
        int ice = frozen(self);
        now = now_ms();
        if (v->ours == want && (visible || now - v->shown_ms < RESHOW_MS)) {
            if (visible) {
                v->reshows = 0;
            }
            /* up already, or still on its way: the new data is in the scene, a sleeping engine would not draw it */
            if (ice != 0) {
                if (ice == 1 && v->wakes < MAX_WAKE_LINES) {
                    ++v->wakes;
                    say("view %d: the engine slept under the %s scene (frame visible %d), woken (%d)",
                        (int)(v - views), scene_name(want), visible, v->wakes);
                }
                guide_start(self);
            }
            return;
        }
        if (v->ours == want) {
            if (v->reshows >= MAX_RESHOWS) {
                return;         /* asked often enough, this view does not draw it */
            }
            ++v->reshows;
        } else {
            v->reshows = 0;     /* the first time, or the other one of our two scenes was up */
        }
        say("view %d: %s scene on (style %d, was ours %d, frame visible %d, engine frozen %d, try %d)",
            (int)(v - views), scene_name(want), *(int *)((char *)self + OFF_STYLE), v->ours, visible, ice, v->reshows);
        /* no unfreeze before it: switch_scene does that itself once the scene is set (see the top of the file) */
        show_scene(self, want, (char *)self + OFF_OWN_MANEUVER);
        if (*(int *)((char *)self + OFF_SCENE_TYPE) != want) {
            /* a style without that scene (the head-up display's style 6 has no follow scene), or the service was not ready */
            say("view %d: the service is at scene type %d after that, not at the %s scene", (int)(v - views),
                *(int *)((char *)self + OFF_SCENE_TYPE), scene_name(want));
        }
        v->ours = want;
        v->shown_ms = now;
    } else if (want == 0) {
        if (v->ours) {
            v->ours = 0;
            say("view %d: hands off (Audi's navigation guides, or this view is not asked for), the scenes are its own again",
                (int)(v - views));
        }
    } else if (v->ours) {
        v->ours = 0;
        say("view %d: phone stopped, back to the empty scene", (int)(v - views));
        guide_stop(self);
    }
}

static void hook_route(void *self, void *elements)
{
    set_route(self, elements);
    after_route(self);
}

/* The DSIKOMOView base sits THUNK_ADJUST bytes into the object; the stock thunk is "sub r0, #4; b setRouteInfo". */
static void hook_route_thunk(void *base, void *elements)
{
    void *self = (char *)base - THUNK_ADJUST;
    set_route(self, elements);
    after_route(self);
}

static const void *code_of(uintptr_t fn)
{
    return (const void *)(fn & ~(uintptr_t)1);
}

static int writable(void *addr)
{
    long page = sysconf(_SC_PAGESIZE);
    uintptr_t start;
    if (page <= 0) {
        page = 4096;
    }
    start = (uintptr_t)addr & ~((uintptr_t)page - 1);
    return mprotect((void *)start, (size_t)page, PROT_READ | PROT_WRITE) == 0;
}

/* Returns 1 when the hook is in place. Never touches a navStartup it does not know. */
int komo_hook_arm(void)
{
    uintptr_t *vt;
    uintptr_t anchor;
    const struct build *known = NULL;
    int b, i;

    if (armed) {
        return 1;
    }
    if (access(SWITCH_FILE, F_OK) != 0) {
        say("switch %s is not there, nothing hooked", SWITCH_FILE);
        return 0;
    }
    vt = (uintptr_t *)dlsym(RTLD_DEFAULT, VT_SYMBOL);
    if (vt == NULL) {
        say("no %s in this process (pid %d), nothing hooked", VT_SYMBOL, (int)getpid());
        return 0;
    }
    anchor = vt[SLOT_ANCHOR];
    /*
     * Which build: loaded at (vt - link address), a relocated slot points into that image (an
     * unrelocated one does not), and the five slots lie where that build has them.
     */
    for (b = 0; b < n_builds && known == NULL; ++b) {
        if ((anchor & ~(uintptr_t)1) != (uintptr_t)vt - builds[b].vtable + (builds[b].anchor & ~(uintptr_t)1)) {
            continue;
        }
        known = &builds[b];
        for (i = 0; i < 5; ++i) {
            if (vt[slot_index[i]] - anchor != builds[b].slot[i] - builds[b].anchor) {
                known = NULL;
            }
        }
    }
    if (known == NULL) {
        /* the distances as they are here: what a port to this build starts from */
        say("none of the %d builds of navStartup this was written for (vtable %p, slot %d %#lx, slots 13/14/22/26/43 "
            "at %#lx %#lx %#lx %#lx %#lx from it, or not relocated yet); nothing hooked", n_builds, (void *)vt,
            SLOT_ANCHOR, (unsigned long)anchor, (unsigned long)(vt[SLOT_GUIDE_START] - anchor),
            (unsigned long)(vt[SLOT_GUIDE_STOP] - anchor), (unsigned long)(vt[SLOT_SET_ROUTE] - anchor),
            (unsigned long)(vt[SLOT_SHOW_SCENE] - anchor), (unsigned long)(vt[SLOT_ROUTE_THUNK] - anchor));
        return 0;
    }
    if (memcmp(code_of(vt[SLOT_SET_ROUTE]), code_set_route, sizeof code_set_route) != 0
            || memcmp(code_of(vt[SLOT_ROUTE_THUNK]), code_thunk, sizeof code_thunk) != 0) {
        say("%s by its addresses, but the code at setRouteInfo or its thunk differs; nothing hooked", known->name);
        return 0;
    }
    if (!writable(&vt[SLOT_SET_ROUTE]) || !writable(&vt[SLOT_ROUTE_THUNK])) {
        say("the vtable cannot be written, nothing hooked");
        return 0;
    }
    guide_start = (fn_self)vt[SLOT_GUIDE_START];
    guide_stop  = (fn_self)vt[SLOT_GUIDE_STOP];
    set_route   = (fn_route)vt[SLOT_SET_ROUTE];
    show_scene  = (fn_scene)vt[SLOT_SHOW_SCENE];
    vt[SLOT_SET_ROUTE]   = (uintptr_t)hook_route;
    vt[SLOT_ROUTE_THUNK] = (uintptr_t)hook_route_thunk;
    armed = 1;
    {
        /* The engine's class, to read its freeze flag: only when its vtable lies where this build has it. */
        uintptr_t ev = (uintptr_t)dlsym(RTLD_DEFAULT, ENGINE_SYMBOL);
        engine_vptr = ev != 0 && ev - (uintptr_t)vt == known->engine - known->vtable ? ev + 2 * sizeof(uintptr_t) : 0;
    }
    say("hooked setRouteInfo of KomoViewService (%s, vtable %p, pid %d, navhook6, engine flag %s)", known->name,
        (void *)vt, (int)getpid(), engine_vptr != 0 ? "readable" : "not readable: woken on every call");
    return 1;
}

static void *alive(void *arg)
{
    unsigned left = ALIVE_S;
    (void)arg;
    while (left > 0) {
        left = sleep(left);
    }
    unlink(FAILS_FILE);
    say("the navigation runs for %d s with the hook in place, start counted as good", ALIVE_S);
    return NULL;
}

static int read_fails(void)
{
    char buf[8];
    int n, fails = 0, fd = open(FAILS_FILE, O_RDONLY);
    if (fd < 0) {
        return 0;
    }
    n = (int)read(fd, buf, sizeof buf - 1);
    close(fd);
    if (n > 0 && buf[0] >= '0' && buf[0] <= '9') {
        fails = buf[0] - '0';
        if (n > 1 && buf[1] >= '0' && buf[1] <= '9') {
            fails = MAX_FAILS;          /* two digits: more than enough */
        }
    }
    return fails;
}

static void put_file(const char *path, char c)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd >= 0) {
        if (write(fd, &c, 1) < 0) {
            /* nothing to do about it */
        }
        close(fd);
    }
}

/* Runs once when the library is loaded. */
void komo_hook_init(void)
{
    static int done;
    pthread_t th;
    pthread_attr_t attr;
    int fails;

    if (done) {
        return;
    }
    done = 1;
    if (access(SWITCH_FILE, F_OK) != 0) {
        say("loaded into pid %d; switch %s is off, nothing hooked", (int)getpid(), SWITCH_FILE);
        return;
    }
    if (dlsym(RTLD_DEFAULT, VT_SYMBOL) == NULL) {
        say("loaded into pid %d, which is not the navigation; nothing hooked", (int)getpid());
        return;
    }
    unlink(TRY_FILE);
    fails = read_fails();
    if (access(BOOT_FILE, F_OK) == 0) {
        ++fails;
        put_file(FAILS_FILE, (char)('0' + (fails > 9 ? 9 : fails)));
        say("the navigation was started again in this boot (%d such starts in a row); not hooked this time", fails);
        return;
    }
    put_file(BOOT_FILE, '1');
    if (fails >= MAX_FAILS) {
        say("%d restarts with the hook in a row; not hooked until %s is deleted", fails, FAILS_FILE);
        return;
    }
    if (!komo_hook_arm()) {
        return;
    }
    if (pthread_attr_init(&attr) == 0) {
        pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
        if (pthread_create(&th, &attr, alive, NULL) != 0) {
            say("no thread for the start check; %s stays until the next start", TRY_FILE);
        }
        pthread_attr_destroy(&attr);
    }
}

#ifndef KOMO_TEST
/* DT_INIT is set to komo_hook_init by build.sh; this covers a loader that runs DT_INIT_ARRAY only. */
static void __attribute__((constructor)) komo_hook_load(void)
{
    komo_hook_init();
}
#endif
