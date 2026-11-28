/*
 * HudTurnFeed - trial: the phone's next turn on the head-up display.
 * Copyright (c) 2026 CrEaK (https://github.com/CrEaK). GPL-3.0-or-later.
 *
 * Off unless the installer wrote /mnt/app/eso/bin/apps/cluster/hud_feed (from
 * Mods/ClusterIntegration/hud_arrows.txt): without that file wrap() hands the
 * service back untouched and nothing here runs.
 *
 * Why this way. On a cockpit coded for the map the turn arrows are not sent
 * over BAP (see the README, "CarPlay on Audi"). The head-up display gets its
 * picture from another place: Audi's navigation hands a pair of
 * org.dsi.ifc.komoview.RouteInfoElement to
 * de.audi.tghu.navi.app.cluster.MOSTHUDKDKHandler.setRouteInfo(), which passes
 * it to the DSIKOMOView service (instance HUD) that draws the manoeuvre
 * (NaviClusterCommonExtension.updateKOMOFollowInfo() in the stock code, read
 * in the P2711 and P2873 images). The handler only exists when the car is
 * coded for it (UtilFrameworkAccess.hasMOSTHUD). The manoeuvre element uses
 * the BAP numbering (TURN = 13 ...) and the BAP direction, which is what the
 * Android Auto and CarPlay integrations already compute for
 * CombiBAPServiceNavi.
 *
 * The head-up display has a second, text path: the same stock class feeds a
 * KOMOCaller of its own (getKomoCallerHUD(), DSIKOMONavInfo instance HUD) with
 * setDistanceToNextManeuver(value, unit, valid) and setTurnToStreet(street, "")
 * next to setCurrentStreet. The first trial (hud2, an Audi on P2711 with
 * wireless CarPlay, 2026-11-26) fed only the element pair: the handler took 73
 * pairs without an error and the display kept showing the current street. So
 * this version also feeds the text path, takes the first element of the pair
 * from the navigation's own followInfoRIE as the stock code does, hands the
 * display back through updateKOMOFollowInfo() when the phone's guidance ends,
 * and a watcher thread writes down what the navigation itself puts into the
 * handler and the caller (the reference for a drive with Audi's own guidance)
 * and sends ours again when the navigation replaced it.
 *
 * So this class sits between those integrations and CombiBAPServiceNavi as a
 * java.lang.reflect.Proxy: every call is forwarded unchanged, and
 * updateRGStatus / updateManeuverDescriptor / updateDistanceToNextManeuver /
 * updateTurnToInfo are also turned into the element pair for the HUD handler.
 * The handler is reached from the navigation's CombiBAPListener, which the
 * mod's CombiBAPServiceNaviListenerWrapper sees when the navigation registers
 * it. Everything is reflection inside catch-alls; one line per change goes to
 * hud-feed.log in the ModKit log folder (copied to the card by the next
 * ModKit run), so a car without a head-up display handler says so there.
 *
 * With the hook in navStartup (below) a head-up display showed an arrow for the first time on 2026-11-27,
 * on its style 5 (hudSetting 2: follow_hud.svg, arrow and distance); it did not follow the manoeuvres yet,
 * see "The freeze".
 *
 * The cockpit's box (trial komo1, marker cluster/komo_feed). The picture the
 * cockpit shows at the right while Audi's navigation guides comes from the same
 * renderer (navStartup, KomoViewService, instance cluster): the "follow" scene
 * is assets/olympia/.../294x320/follow/follow.svg with the destination from the
 * first element of the pair (%FLAG% %ETA% %DTD%) and the next manoeuvre from
 * the second (%ARROW% %D_PREFIX% %DTNM%). For the cockpit the stock code sends
 * the pair through KOMOService -> KOMOCaller -> DSIKOMOView.setRouteInfo(). With
 * the marker, KOMOCaller.komoView of the cockpit is replaced by a proxy that
 * forwards every call and, while the phone guides, swaps the second element for
 * the phone's manoeuvre; a change at the phone is sent with the navigation's
 * last first element. The scene itself is switched by Audi's own guidance, so
 * this shows something only while an Audi route runs as well. The proxy takes
 * no lock of this class (it is called inside KOMOCaller's monitor).
 *
 * Showing the box without an Audi route (trial komo2, marker cluster/komo_show).
 * The cockpit shows the box when ClusterKDKHandlerFPK publishes "KDK visible"
 * (hint 4 in the HMI models 168 and 4652), which refreshState() does when the
 * renderer is enabled, the navigation guides (updateRgActive) and the renderer
 * reported a picture (DSIKOMOView attribute visibility -> updateKOMOViewVisible).
 * The renderer reports a picture only for a scene other than its empty one
 * (on_rendered: "EmptyScene" freezes it and sets the frame invisible), and its
 * scenes follow Audi's own guidance. With the marker, while the phone guides and
 * Audi does not, both inputs of the handler are set by hand, to see whether the
 * cockpit then makes room for the box. What the box holds then is the renderer's
 * empty picture: this trial is about the room, not the content.
 *
 * The content (trial navhook1/komo3). src/navhook/komo_hook.c, preloaded into
 * navStartup, switches the renderer to its "follow" scene when the first byte
 * of /tmp/komo_follow is '1'. This class keeps that file while komo_show is
 * set: '1' while the phone guides and Audi does not, '0' while both guide (the
 * scenes are Audi's), no file otherwise. The hook looks at the file on every
 * setRouteInfo, so the file is written before the pair goes out, and a change
 * of the file alone is followed by sending the current pair once more.
 *
 * With the hook in navStartup (switch cluster/komo_hook) the renderer reports its
 * picture itself, so only "guidance runs" is set by hand. Setting and clearing
 * "has a picture" by hand as well left the handler and the renderer apart after a
 * CarPlay route: the Audi box then stayed away until the next MMI start (A6 C8,
 * 2026-11-27). The watcher writes the handler's inputs to the log when they change.
 *
 * The freeze (komo8). On 2026-11-27 the box of an A6 stopped following a few seconds after a second route
 * had started, and on a car with a head-up display the arrow there stayed at the phone's first data. The
 * cause is in the hook's first version (see src/navhook/komo_hook.c): the render engine went to sleep under
 * the follow scene. The hook now wakes it inside setRouteInfo, and the watcher sends the current pair every
 * few seconds while the phone guides, so that a parked car gets such a call as well.
 *
 * The phone goes away (komo13). CarPlay's turn hook writes its state only when the phone sends something, so
 * a session that ends leaves the last route standing and the box up. phoneWatch() takes everything back when
 * the map hook's session file goes (or, with an older map hook, the phone's cockpit video) while CarPlay
 * guides, and goes on when the phone speaks again. Not seen on a car yet.
 *
 * The cockpit's tab (komo11, komo12). cockpit() writes down what the cockpit tells the navigation about its
 * display, and the handler's line carries its layout fields. On an A6 (2026-11-28) a change of the tab away
 * from the map and back showed as IMapClusterService.switchKombiMapToHiddenContext / ...ToAShownContext; the
 * BAP indication setMapVisibility did not come, and the view size showed only in the handler's "big stage".
 * The cockpit kept the box in every tab. With the switch cluster/komo_tab (trial) the box is taken away while
 * the cockpit shows the map and that map is the phone's (/tmp/altscreen_video), and comes back in the other
 * tabs. Not seen on a car yet.
 *
 * One wish per view (komo10). The hook (navhook6) tells the head-up display's view from the cockpit's by its
 * style variant and reads two bytes from the follow flag file, the cockpit's and the head-up display's. The
 * cockpit's is set with komo_show, the head-up display's with hud_feed and komo_hook, so the arrow on the
 * head-up display works without the box in the cockpit and the other way round. Both together write the one
 * byte of before. Not seen on a car yet.
 *
 * The flag at the destination (komo9, trial, switch cluster/komo_dest). Audi's own guidance changes from
 * the arrow to a picture with a flag near the destination. That picture is a scene of its own in the renderer
 * (type 5, "destination"), a fixed image that needs nothing from Audi's route. With the switch, the follow
 * flag file holds '5' in place of '1' once the phone's next manoeuvre is the arrival (element 3) and 200 m
 * away or nearer; the hook (navhook5) then shows that scene. Without the switch nothing changes. An older
 * hook reads '5' as "hands off", so the switch belongs to navhook5 only. Not seen on a car yet.
 *
 * Arrival and remaining distance (komo5). The upper half of the box comes from the
 * first element: etaHours / etaMinutes / etaTimeFormat and distance / distanceFormat /
 * distanceUnit (Audi's own on the car: {distance=48, distanceFormat=1, etaHours=18,
 * etaMinutes=10, decimalMark=",", distanceUnit="km"}). The phone integrations give
 * the remaining seconds (updateTimeToDestination) and metres
 * (updateDistanceToDestination). The arrival is the car's local time
 * (ISysServices.clock().localTime(), reached through the extension's navigationEnv)
 * plus the remaining seconds, read as the stock code reads its arrival time
 * (KOMOService.convertTimeToKOMO: Date and GregorianCalendar, here in GMT because the
 * value is local time already). What the clock gave is written to the log once.
 *
 * Java 1.4 source level.
 */
package de.audi.app.terminalmode.smartphone.androidauto2.nav;

import de.audi.atip.interapp.combi.bap.navi.data.CombiBAPNaviManeuverDescriptor;
import de.audi.atip.interapp.combi.bap.navi.data.DistanceUnit;
import de.audi.tghu.navi.app.osgi.wrapper.CombiBAPServiceNaviListenerWrapper;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.lang.reflect.Proxy;
import java.util.Calendar;
import java.util.Date;
import java.util.GregorianCalendar;
import java.util.TimeZone;

import org.dsi.ifc.komoview.ManeuverElement;
import org.dsi.ifc.komoview.RouteInfoElement;
import org.dsi.ifc.komoview.TrafficInfo;

public final class HudTurnFeed implements InvocationHandler, Runnable {
    private static final String MARKER = "/mnt/app/eso/bin/apps/cluster/hud_feed";
    private static final String LOG_DIR = "/mnt/ota/modkit/Logs";
    private static final String LOG_MAIN = LOG_DIR + "/hud-feed.log";
    private static final String LOG_TMP = "/tmp/hud-feed.log";
    /** Written by the hook in the navigation process (src/navhook/komo_hook.c). */
    private static final String HOOK_LOG = "/tmp/komo_hook.log";
    private static long hookLogAt;
    private static volatile int viewCalls;
    private static final long LOG_LIMIT = 256L * 1024L;
    private static final String KOMO_MARKER = "/mnt/app/eso/bin/apps/cluster/komo_feed";
    private static final String SHOW_MARKER = "/mnt/app/eso/bin/apps/cluster/komo_show";
    private static final String FOLLOW_FLAG = "/tmp/komo_follow";
    private static final String HOOK_SWITCH = "/mnt/app/eso/bin/apps/cluster/komo_hook";
    private static final String BUILD = "komo13";
    /* the dio_manager hook keeps this file from a CarPlay session's start to its end (altscreen.so "ui2" and later) */
    private static final String PHONE_SESSION = "/tmp/altscreen_session";
    private static boolean sessionSeen, sessionEver, videoSeen;
    /* the phone went away while it guided: our output is taken back until it says something again */
    private static boolean phoneGone;
    private static String lastSource = "";
    /* trial: the box in the cockpit only while the cockpit does not show the map (the phone's map draws its own turn card) */
    private static final String TAB_SWITCH = "/mnt/app/eso/bin/apps/cluster/komo_tab";
    /* the dio_manager hook keeps this file while the phone's map runs on the cockpit */
    private static final String PHONE_MAP = "/tmp/altscreen_video";
    private static final Object WAKE = new Object();
    private static boolean woken;
    private static boolean tabHidden;
    /* trial: near the end of the phone's route the hook shows the renderer's destination scene (the flag) */
    private static final String DEST_SWITCH = "/mnt/app/eso/bin/apps/cluster/komo_dest";
    /* EManeuverElement DESTINATION, as the phone integrations send the arrival */
    private static final int ELEMENT_DESTINATION = 3;
    private static final int DEST_METERS = 200;
    private static boolean destScene;
    /* the phone gave a distance after the manoeuvre last changed: the one before belongs to the turn just passed */
    private static boolean distFresh;
    private static final long WATCH_MS = 2000L;
    /* while the hook shows the follow scene: the current pair once more every so many watcher rounds */
    private static final int BEAT_ROUNDS = 2;
    private static int beat;
    /* what the cockpit last said about its map area, one text per kind (see cockpit()) */
    private static final Object COCKPIT = new Object();
    private static final String[] cockpitLast = new String[8];
    private static int cockpitLines;
    /** The cockpit shows the map in its centre (the navigation's map context, see mapContext(); true until told otherwise). */
    public static volatile boolean mapShown = true;
    /* whether the next tick() sends to the cockpit's view as well */
    private static boolean tickBox = true;
    /* the navigation's own data: a line when it changes in kind, distance steps at most this often */
    private static final long QUIET_MS = 10000L;

    /* DSIKOMOView.ROUTEINFOELEMENTTYPE_RIE_MANEUVER; EManeuverElementEelement.SIDE_STREET */
    private static final int RIE_MANEUVER = 3;
    private static final int ELEMENT_SIDE_STREET = 128;

    private static final Object LOCK = new Object();

    /* the phone's guidance as last sent to CombiBAPServiceNavi (one phone at a time) */
    private static int rgStatus;
    private static int mainElement = -1;
    private static int direction;
    private static byte[] sideStreets;
    private static int distValue = -1;      /* BAP: tenths of the unit */
    private static int distUnit;
    private static boolean bargraphOn;
    private static long destSec = -1L;      /* remaining seconds to the destination */
    private static int destMeters = -1;
    private static int destUnit;            /* BAP unit the phone wants: 0 metric, 4 miles */
    private static String road = "";
    private static String signPost = "";

    private static Object handler;
    private static Object ext;              /* NaviClusterCommonExtension */
    private static Object hudCaller;        /* its KOMOCaller for the HUD text path */
    private static Object ourPair;          /* the array we handed to the handler last */
    private static boolean textSent;
    private static long textValue = -1L;
    private static int textUnit = 255;
    private static boolean textValid;
    private static String textRoad = "";
    private static boolean watching;
    private static long replaced;
    private static long textReplaced;
    private static String lastFirst = "";
    private static final Object REC = new Object();
    private static final String[] recShape = new String[3];
    private static final String[] recFull = new String[3];
    private static final long[] recTime = new long[3];

    /* the cockpit's box; the volatile ones are read by the view proxy without LOCK */
    private static volatile Object clusterView;                 /* the real DSIKOMOView of the cockpit */
    private static volatile Object clusterProxy;                /* what KOMOCaller.komoView holds now */
    private static volatile RouteInfoElement clusterTurn;       /* the phone's manoeuvre while it guides */
    private static volatile RouteInfoElement[] audiPair;        /* what the navigation sent last */
    private static volatile String audiPrefix;
    private static volatile String audiDecimal;
    private static volatile String ownDecimal;                  /* the HMI's decimal mark, from Audi's formatter */
    /* the phone's destination for the first element: hour, minute, time format (2 = none), distance, distance format */
    private static volatile int[] destInfo;
    private static volatile String destUnitText;
    private static String lastDest = "";
    private static int clockLogged;         /* 0 nothing yet, 1 logged without a time, 2 logged with one */
    private static Object clusterCaller;
    private static boolean clusterSent;
    private static long clusterPushes;
    private static volatile long swapped;
    private static String lastBox = "";
    private static boolean kdkForced;
    private static boolean kdkForcedVisible;    /* we set "the renderer has a picture" by hand */
    private static String lastKdkWatch = "";
    private static long kdkAsserts;
    private static String lastKdk = "";
    private static int followState = -2;    /* what FOLLOW_FLAG stands for: -2 unknown, -1 no file, 0 hands off, else scene * 100 + 10 (cockpit) + 1 (head-up display) */
    private static String lastNote = "";
    private static String lastState = "";
    private static String lastPush = "";
    private static boolean sentActive;
    private static long pushes;

    private final Object target;
    private final String source;
    private final boolean view;             /* proxy in front of the cockpit's DSIKOMOView */

    private HudTurnFeed(Object target, String source) {
        this(target, source, false);
    }

    private HudTurnFeed(Object target, String source, boolean view) {
        this.target = target;
        this.source = source;
        this.view = view;
    }

    /**
     * Returns the service itself, or with the marker installed a proxy that
     * forwards to it and feeds the head-up display. Never throws.
     */
    public static Object wrap(Object service, String source) {
        if (service == null) {
            return null;
        }
        try {
            if (!new File(MARKER).exists() && !new File(KOMO_MARKER).exists() && !new File(SHOW_MARKER).exists()) {
                return service;
            }
            Class ifc = Class.forName("de.audi.atip.interapp.combi.bap.navi.CombiBAPServiceNavi");
            if (!ifc.isInstance(service)) {
                log("wrap " + source + ": " + service.getClass().getName() + " is not a CombiBAPServiceNavi, left alone");
                return service;
            }
            Object proxy = Proxy.newProxyInstance(ifc.getClassLoader(), new Class[] { ifc },
                    new HudTurnFeed(service, source));
            log("wrap " + source + ": feeding from " + service.getClass().getName() + ", level " + readLevel()
                    + ", cockpit box " + (komoOn() ? "on" : "off") + ", shown without an Audi route "
                    + (showOn() ? "on" : "off") + " (" + BUILD + ")");
            startWatch();
            return proxy;
        } catch (Throwable t) {
            log("wrap " + source + " failed, service left alone: " + t);
            return service;
        }
    }

    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        Object result;
        if (this.view) {
            Object[] a = args;
            try {
                a = viewArgs(method.getName(), args);
            } catch (Throwable t) {
                a = args;
                note("cockpit box: " + method.getName() + " passed on unchanged: " + t);
            }
            try {
                return method.invoke(this.target, a);
            } catch (InvocationTargetException e) {
                throw e.getTargetException();
            }
        }
        try {
            result = method.invoke(this.target, args);
        } catch (InvocationTargetException e) {
            throw e.getTargetException();
        }
        try {
            this.tap(method.getName(), args);
        } catch (Throwable t) {
            note("tap " + method.getName() + " failed: " + t);
        }
        return result;
    }

    private void tap(String name, Object[] a) {
        if (a == null) {
            return;
        }
        synchronized (LOCK) {
            boolean changed = false;
            boolean ended = false;
            boolean back = false;
            if ("updateRGStatus".equals(name) && a.length == 1) {
                int v = ((Integer) a[0]).intValue();
                if (phoneGone) {
                    /* the first word after the phone was gone is about a new route: nothing of the old one counts */
                    phoneGone = false;
                    forgetRoute();
                    log("the phone is back (" + this.source + " " + name + " " + v + ")");
                }
                changed = v != rgStatus;
                ended = rgStatus == 1 && v != 1;
                rgStatus = v;
            } else if ("updateManeuverDescriptor".equals(name) && a.length == 1) {
                Object[] list = (Object[]) a[0];
                CombiBAPNaviManeuverDescriptor d = list != null && list.length > 0
                        ? (CombiBAPNaviManeuverDescriptor) list[0] : null;
                int element = d != null ? d.mainElement : -1;
                int dir = d != null ? d.direction : 0;
                byte[] side = d != null ? d.sideStreets : null;
                changed = element != mainElement || dir != direction || !same(side, sideStreets);
                if (element != mainElement) {
                    distFresh = false;
                }
                mainElement = element;
                direction = dir;
                sideStreets = side;
            } else if ("updateDistanceToNextManeuver".equals(name) && a.length == 4) {
                int value = ((Integer) a[0]).intValue();
                int unit = ((Integer) a[1]).intValue();
                boolean bar = ((Boolean) a[2]).booleanValue();
                changed = value != distValue || unit != distUnit || bar != bargraphOn;
                distFresh = true;
                distValue = value;
                distUnit = unit;
                bargraphOn = bar;
            } else if ("updateTimeToDestination".equals(name) && a.length == 3) {
                long sec = ((Long) a[2]).longValue();
                changed = sec != destSec;
                destSec = sec;
            } else if ("updateDistanceToDestination".equals(name) && a.length == 3) {
                int m = ((Integer) a[0]).intValue();
                int u = a[1] != null ? ((DistanceUnit) a[1]).value() : 0;
                changed = m != destMeters || u != destUnit;
                destMeters = m;
                destUnit = u;
            } else if ("updateTurnToInfo".equals(name) && a.length == 2) {
                String r = a[0] != null ? (String) a[0] : "";
                String s = a[1] != null ? (String) a[1] : "";
                changed = !r.equals(road) || !s.equals(signPost);
                road = r;
                signPost = s;
            } else {
                return;
            }
            lastSource = this.source;
            if (phoneGone) {
                /* data flows, so the phone is there after all (its video ended, not its session): go on where it was */
                phoneGone = false;
                rgStatus = 1;
                back = true;
                log("the phone is back (" + this.source + " " + name + "), its guidance goes on");
            }
            if (changed || back) {
                push(this.source + " " + name);
            }
            if (ended) {
                forgetRoute();
            }
        }
    }

    /*
     * LOCK held, from the watcher. CarPlay's turn hook never says that the phone is gone: its state keeps the
     * last route, and the box stayed up after CarPlay was switched off in the MMI (A6, 2026-11-28). The map
     * hook in the same process keeps a file for the length of the session; where an older one does not, the
     * end of the phone's cockpit video stands in. When that goes while CarPlay guides, everything of ours is
     * taken back as at the end of a route; the route's data stays until the phone says something again.
     */
    private static void phoneWatch() {
        boolean session = false;
        boolean video = false;
        try {
            session = new File(PHONE_SESSION).exists();
            video = new File(PHONE_MAP).exists();
        } catch (Throwable t) {
            return;
        }
        boolean went = sessionEver ? sessionSeen && !session : videoSeen && !video;
        sessionEver |= session;
        sessionSeen = session;
        videoSeen = video;
        if (went && rgStatus == 1 && !phoneGone && "CarPlay".equals(lastSource)) {
            phoneGone = true;
            rgStatus = 0;
            log("the phone is gone (CarPlay's " + (sessionEver ? "session" : "cockpit video")
                    + " ended while it guided): the turn is taken back");
            push("CarPlay gone");
        }
    }

    /*
     * LOCK held. The phone's guidance ended: nothing of this route may be shown for the next one. Seen on
     * an A6, 2026-11-27: a route in one app, then one in another, and the box opened with the first app's
     * arrow, distance and arrival until the second app had sent its own. The phone integrations forget
     * what they sent when a route ends and send the next route's manoeuvre in full.
     */
    private static void forgetRoute() {
        destScene = false;
        distFresh = false;
        mainElement = -1;
        direction = 0;
        sideStreets = null;
        distValue = -1;
        distUnit = 0;
        bargraphOn = false;
        road = "";
        signPost = "";
        destSec = -1L;
        destMeters = -1;
        destUnit = 0;
        destInfo = null;
        lastDest = "";
    }

    private static boolean same(byte[] a, byte[] b) {
        if (a == b) {
            return true;
        }
        if (a == null || b == null || a.length != b.length) {
            return false;
        }
        for (int i = 0; i < a.length; ++i) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    /*
     * Called inside KOMOCaller's monitor, on the navigation's thread: no LOCK here. Remembers the
     * navigation's pair and, while the phone guides, hands on its first element with our manoeuvre.
     */
    private static Object[] viewArgs(String name, Object[] args) throws Exception {
        if (!"setRouteInfo".equals(name) || args == null || args.length != 1) {
            viewCall(name, args);
            return args;
        }
        RouteInfoElement[] in = (RouteInfoElement[]) args[0];
        audiPair = in;
        if (in != null && in.length > 1 && in[1] != null) {
            if (in[1].distancePrefix != null) {
                audiPrefix = in[1].distancePrefix;
            }
            if (in[1].decimalMark != null) {
                audiDecimal = in[1].decimalMark;
            }
        }
        record(2, "navigation's cockpit pair", describePair(in, false), describePair(in, true));
        RouteInfoElement turn = clusterTurn;
        if (turn == null || !komoOn()) {
            return args;
        }
        RouteInfoElement[] out = mix(in, turn);
        long n = ++swapped;
        if (n == 1 || n % 50 == 0) {
            log("cockpit box: put the phone's manoeuvre into the navigation's pair (" + n + " times so far)");
        }
        return new Object[] { out };
    }

    /*
     * What else the navigation's Java side tells the renderer (enableKomoView, notifyVisibility,
     * setKomoViewStyle): written down, because on an A6 the picture stopped following a few seconds after
     * a route in a second app had started (2026-11-27), while the pairs kept going out.
     */
    private static void viewCall(String name, Object[] args) {
        if ("toString".equals(name) || "hashCode".equals(name) || "equals".equals(name) || viewCalls >= 300) {
            return;
        }
        ++viewCalls;
        StringBuffer b = new StringBuffer("navigation -> renderer: ").append(name).append('(');
        for (int i = 0; args != null && i < args.length; ++i) {
            b.append(i > 0 ? ", " : "").append(args[i] instanceof Object[] ? "[" + ((Object[]) args[i]).length + "]"
                    : String.valueOf(args[i]));
        }
        log(b.append(')').toString());
    }

    /* The navigation's first element (destination) with the phone's manoeuvre as the second. No LOCK needed. */
    private static RouteInfoElement[] mix(RouteInfoElement[] audi, RouteInfoElement turn) throws Exception {
        RouteInfoElement first = audi != null && audi.length > 0 && audi[0] != null ? copy(audi[0]) : blank();
        RouteInfoElement second = copy(turn);
        String prefix = audiPrefix;
        second.distancePrefix = prefix != null ? prefix : "in";
        second.decimalMark = decimalMark();
        first.distanceToManeuver = second.distanceToManeuver;   /* as updateNextManeuver() does */
        applyDest(first);
        return new RouteInfoElement[] { first, second };
    }

    private static boolean komoOn() {
        try {
            return new File(KOMO_MARKER).exists();
        } catch (Throwable t) {
            return false;
        }
    }

    /* LOCK held. The phone's state changed: send it to the cockpit's view, or hand the box back. */
    private static void cluster(String why) {
        boolean active = komoOn() && rgStatus == 1 && mainElement >= 0;
        if (!active && !clusterSent && clusterTurn == null) {
            return;
        }
        RouteInfoElement turn = active ? turn(1) : null;
        clusterTurn = turn;
        if (clusterView == null) {
            hookCluster();
        }
        Object v = clusterView;
        if (v == null) {
            clusterSent = false;
            return;
        }
        try {
            RouteInfoElement[] audi = audiPair;
            RouteInfoElement[] out = active ? mix(audi, turn) : audi;
            if (out == null && showOn()) {
                out = new RouteInfoElement[] { blank(), blank() };      /* the hook needs a call to notice the end */
            }
            if (out != null) {
                call(v, "setRouteInfo", new Class[] { out.getClass() }, new Object[] { out });
                ++clusterPushes;
            }
            clusterSent = active;
            String line = active
                    ? "turn element " + mainElement + " direction " + direction + ", road \"" + road + "\""
                    : (out == null ? "handed back (the navigation sent none)"
                            : out == audi ? "handed back (the navigation's last pair)" : "handed back (blank pair)");
            if (!line.equals(lastBox)) {
                lastBox = line;
                log("cockpit box " + clusterPushes + " (" + why + "): " + line
                        + (active ? ", distance " + distValue + " unit " + distUnit + " (\"" + distanceText()
                                + "\"); sent " + describePair(out, true) : ""));
            }
        } catch (Throwable t) {
            note("cockpit box: sending failed: " + t);
        }
    }

    private static boolean showOn() {
        try {
            return new File(SHOW_MARKER).exists();
        } catch (Throwable t) {
            return false;
        }
    }

    /*
     * LOCK held. While the phone guides and Audi's navigation does not: tell the cockpit's KDK handler
     * that guidance runs and that the renderer has a picture, so it publishes "KDK visible". Taken back
     * when the phone stops or the marker goes; left alone as soon as Audi guides itself.
     */
    private static void showBox(String why) {
        boolean want = showOn() && rgStatus == 1 && mainElement >= 0;
        /*
         * komo_tab: no box while the cockpit shows the map and that map is the phone's, which draws its own turn
         * card and arrival. In every other tab the cockpit keeps the box (A6, 2026-11-28), as with Audi's own
         * guidance. Only the handler's "guidance runs" is taken back; the scene stays up and current, so the box
         * is there at once when the tab changes.
         */
        boolean hide = want && tabHides();
        if (hide != tabHidden) {
            tabHidden = hide;
            log("cockpit box: " + (hide ? "hidden while the cockpit shows the phone's map (komo_tab)"
                    : "the cockpit's tab no longer hides it"));
        }
        if (hide) {
            want = false;
            why = why + ", map tab";
        }
        if (!want && !kdkForced) {
            return;
        }
        Object x = findExt();
        if (x == null) {
            return;
        }
        try {
            Object k = field(x, "clusterKDKHandler");
            if (k == null) {
                note("cockpit box: the navigation has no KDK handler");
                return;
            }
            boolean audi = truth(x, "rgActive");
            boolean hook = new File(HOOK_SWITCH).exists();
            Class[] flag = new Class[] { Boolean.TYPE };
            if (want) {
                if (audi) {
                    if (kdkForced) {
                        kdkForced = false;
                        kdkForcedVisible = false;
                        log("cockpit box: Audi's navigation guides now, the box is its own again: " + kdkState(k));
                    }
                    return;
                }
                /* with the hook the renderer says itself when it has a picture; then only "guidance runs" is ours */
                if (kdkForced && truth(k, hook ? "rgActive" : "kdkAvailable")) {
                    return;
                }
                call(k, "updateRgActive", flag, new Object[] { Boolean.TRUE });
                if (!hook) {
                    call(k, "updateKOMOViewVisible", flag, new Object[] { Boolean.TRUE });
                    kdkForcedVisible = true;
                }
                ++kdkAsserts;
                String state = kdkState(k);
                if (!kdkForced || !state.equals(lastKdk) || kdkAsserts % 20 == 0) {
                    log("cockpit box: asked the cockpit to show it without an Audi route (" + kdkAsserts
                            + " times so far, " + why + ", " + (hook ? "picture reported by the renderer" : "picture set by hand")
                            + ", " + k.getClass().getName() + "): " + state);
                }
                lastKdk = state;
                kdkForced = true;
            } else {
                kdkForced = false;
                if (!audi) {
                    if (kdkForcedVisible) {
                        call(k, "updateKOMOViewVisible", flag, new Object[] { Boolean.FALSE });
                    }
                    call(k, "updateRgActive", flag, new Object[] { Boolean.FALSE });
                }
                kdkForcedVisible = false;
                log("cockpit box: no longer asking for it (" + why + "): " + kdkState(k));
            }
        } catch (Throwable t) {
            note("cockpit box: asking the cockpit to show it failed: " + t);
        }
    }

    /*
     * What the cockpit tells the navigation about its own display (komo11). The mod's wrappers around the
     * navigation's cockpit interfaces call this on the cockpit's thread: CombiBAPServiceNaviListenerWrapper for
     * the BAP indications (0 map visibility, 1 map view, 2 presentation, 3 route guidance type) and
     * IMapClusterServiceWrapper for what the navigation makes of them (4 map context shown or hidden, 5 view
     * size). One line when a kind's text changes, so a drive with a few changes of the cockpit's tab shows
     * which of them tells "the map is not on screen": Audi's own guidance shows its box in every tab, and the
     * phone's box should come back there as well. Takes no LOCK and never throws.
     */
    public static void cockpit(int kind, String what) {
        try {
            synchronized (COCKPIT) {
                if (kind < 0 || kind >= cockpitLast.length || what == null || what.equals(cockpitLast[kind])
                        || cockpitLines >= 400) {
                    return;
                }
                cockpitLast[kind] = what;
                ++cockpitLines;
            }
            if (readLevel() > 0 || komoOn() || showOn()) {
                log("cockpit: " + what);
            }
        } catch (Throwable t) {
        }
    }

    private static boolean tabHides() {
        try {
            return mapShown && new File(TAB_SWITCH).exists() && new File(PHONE_MAP).exists();
        } catch (Throwable t) {
            return false;
        }
    }

    /** The cockpit's map area came or went (IMapClusterServiceWrapper): the watcher looks at once. No LOCK. */
    public static void mapContext(boolean shown) {
        mapShown = shown;
        cockpit(4, shown ? "the navigation's cockpit map goes to a shown context" : "the navigation's cockpit map goes to the hidden context");
        try {
            synchronized (WAKE) {
                woken = true;           /* also when the watcher is in the middle of a round */
                WAKE.notifyAll();
            }
        } catch (Throwable t) {
        }
    }

    /* LOCK held. The handler's inputs, written down when they change: who switched the box on or off. */
    private static void watchBox() {
        if (!showOn() && !komoOn()) {
            return;
        }
        try {
            Object x = ext;
            Object k = x != null ? field(x, "clusterKDKHandler") : null;
            if (k == null) {
                return;
            }
            String state = kdkState(k) + "; navigation rgActive " + truth(x, "rgActive") + ", phone guiding "
                    + (rgStatus == 1 && mainElement >= 0);
            if (!state.equals(lastKdkWatch)) {
                lastKdkWatch = state;
                log("cockpit box state: " + state);
            }
        } catch (Throwable t) {
            note("cockpit box: reading the handler failed: " + t);
        }
    }

    private static String kdkState(Object k) {
        try {
            return "komoViewEnabled " + field(k, "komoViewEnabled") + ", komoViewVisible " + field(k, "komoViewVisible")
                    + ", rgActive " + field(k, "rgActive") + ", isInStandBy " + field(k, "isInStandBy") + ", clamp15 "
                    + field(k, "clamp15") + " -> kdkAvailable " + field(k, "kdkAvailable") + ", kdkVisible "
                    + field(k, "kdkVisible") + "; layout: stack design " + opt(k, "isStackDesignActive") + ", big stage "
                    + opt(k, "isInBigStage") + ", intersection map plus " + opt(k, "isIntersectionMapPlusVisible")
                    + ", bar graph rendered " + opt(k, "bargraphRendered");
        } catch (Throwable t) {
            return "state not readable: " + t;
        }
    }

    /* LOCK held. Puts the proxy in front of the cockpit's DSIKOMOView (KOMOService.komoCaller.komoView). */
    private static void hookCluster() {
        try {
            Object x = findExt();
            if (x == null) {
                return;
            }
            Object service = call(x, "getKomoService", new Class[0], new Object[0]);
            Object caller = service != null ? field(service, "komoCaller") : null;
            if (caller == null) {
                note("cockpit box: no KOMOCaller in the navigation's KOMOService");
                return;
            }
            synchronized (caller) {
                Object cur = field(caller, "komoView");
                if (cur == null) {
                    clusterView = null;
                    clusterProxy = null;
                    note("cockpit box: the view service is not registered yet");
                    return;
                }
                if (cur == clusterProxy) {
                    return;
                }
                Class ifc = Class.forName("org.dsi.ifc.komoview.DSIKOMOView");
                Object p = Proxy.newProxyInstance(ifc.getClassLoader(), new Class[] { ifc },
                        new HudTurnFeed(cur, "cockpit view", true));
                setField(caller, "komoView", p);
                clusterCaller = caller;
                clusterView = cur;
                clusterProxy = p;
            }
            log("cockpit box: hooked " + clusterView.getClass().getName() + " (KOMOCaller.komoView)");
        } catch (Throwable t) {
            note("cockpit box: hooking the view service failed: " + t);
        }
    }

    /* LOCK held. Marker gone: the real service goes back into KOMOCaller. */
    private static void unhookCluster() {
        Object caller = clusterCaller;
        Object p = clusterProxy;
        Object real = clusterView;
        clusterTurn = null;
        if (caller == null || p == null) {
            return;
        }
        try {
            synchronized (caller) {
                if (field(caller, "komoView") == p) {
                    setField(caller, "komoView", real);
                }
            }
            log("cockpit box: switched off, the view service is back in place");
        } catch (Throwable t) {
            note("cockpit box: unhooking failed: " + t);
        }
        clusterProxy = null;
        clusterView = null;
        clusterCaller = null;
        clusterSent = false;
    }

    /*
     * LOCK held. Keeps /tmp/komo_follow for the hook in navStartup. Returns true when it changed, so the
     * caller can send a pair for the hook to notice.
     */
    private static boolean followFlag(String why) {
        boolean box = showOn();
        boolean hud = hudScene();
        int want = -1;
        String text = null;
        if ((box || hud) && rgStatus == 1 && mainElement >= 0) {
            if (truth(findExt(), "rgActive")) {
                want = 0;
                text = "0";
            } else {
                char scene = destination() ? '5' : '1';
                /* one byte is for both views (and all an older hook reads); two bytes: the cockpit's, the head-up display's */
                text = box && hud ? String.valueOf(scene) : (box ? scene : '0') + "" + (hud ? scene : '0');
                want = (scene - '0') * 100 + (box ? 10 : 0) + (hud ? 1 : 0);
            }
        }
        if (want == followState) {
            return false;
        }
        try {
            File f = new File(FOLLOW_FLAG);
            if (want < 0) {
                f.delete();
            } else {
                FileOutputStream out = new FileOutputStream(f);
                try {
                    out.write(text.getBytes());
                } finally {
                    out.close();
                }
            }
            if (followState != -2 || want >= 0) {
                log("follow flag for the navigation's renderer: "
                        + (want < 0 ? "removed" : want == 0 ? "0 (Audi guides, hands off)"
                                : text + " (" + (want >= 500 ? "destination scene, " + nextMeters() + " m to go" : "follow scene")
                                        + (box && hud ? ", cockpit and head-up display" : box ? ", cockpit only" : ", head-up display only")
                                        + ")")
                        + " (" + why + ")");
            }
            /* the pair that follows a change goes to the cockpit's view when the change is about it */
            tickBox = boxIn(followState) || boxIn(want) || followState == 0 || want == 0;
            followState = want;
            return true;
        } catch (Throwable t) {
            note("writing " + FOLLOW_FLAG + " failed: " + t);
            return false;
        }
    }

    /* Does this state of the flag file ask for a scene in the cockpit's view? */
    private static boolean boxIn(int state) {
        return state >= 100 && (state / 10) % 10 == 1;
    }

    /*
     * The head-up display's view gets its scene from the hook when the HUD feed is on (hud_feed) and the
     * hook is armed (komo_hook); the box in the cockpit is a matter of komo_show alone. So the arrow on the
     * head-up display does not need the box.
     */
    private static boolean hudScene() {
        try {
            return readLevel() > 0 && new File(HOOK_SWITCH).exists();
        } catch (Throwable t) {
            return false;
        }
    }

    /*
     * LOCK held. The destination scene (switch cluster/komo_dest): once the phone's next manoeuvre is the
     * arrival and it is DEST_METERS away or nearer, and from then on until the manoeuvre changes or the
     * guidance ends, so a distance that jumps back does not flip the picture. The distance has to be one
     * the phone gave after the arrival became the next manoeuvre: right after the last turn the value is
     * still that turn's few metres.
     */
    private static boolean destination() {
        if (destForced()) {
            return true;
        }
        if (mainElement != ELEMENT_DESTINATION) {
            destScene = false;
            return false;
        }
        if (!destScene) {
            int m = nextMeters();
            try {
                destScene = distFresh && m >= 0 && m <= DEST_METERS && new File(DEST_SWITCH).exists();
            } catch (Throwable t) {
                destScene = false;
            }
        }
        return destScene;
    }

    /*
     * For a look at the scene in a parked car, where the phone's next manoeuvre is "start on ..." and never the
     * arrival: a komo_dest that begins with "t" (echo test > komo_dest) shows the destination scene for the
     * whole route.
     */
    private static boolean destForced() {
        FileInputStream in = null;
        try {
            File f = new File(DEST_SWITCH);
            if (!f.exists() || f.length() == 0L) {
                return false;
            }
            in = new FileInputStream(f);
            return in.read() == 't';
        } catch (Throwable t) {
            return false;
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (Throwable t) {
                }
            }
        }
    }

    /* The distance to the next manoeuvre in metres, from the BAP tenths; -1 when the phone gave none. */
    private static int nextMeters() {
        if (distValue < 0) {
            return -1;
        }
        long v = distValue;
        switch (distUnit) {
            case 0: return (int) (v / 10L);                 /* m */
            case 1: case 6: return (int) (v * 100L);        /* km */
            case 2: return (int) (v * 9144L / 100000L);     /* yd */
            case 3: return (int) (v * 3048L / 100000L);     /* ft */
            case 4: case 7: return (int) (v * 1609L / 10L); /* mi */
            case 5: return (int) (v * 402L / 10L);          /* quarter miles */
            default: return -1;
        }
    }

    /* LOCK held. The flag changed without a change at the phone, or the watcher's turn came: send what is current once more. */
    private static void tick() {
        try {
            Object v = clusterView;
            if (v != null && tickBox) {
                RouteInfoElement turn = clusterTurn;
                RouteInfoElement[] audi = audiPair;
                RouteInfoElement[] out = turn != null ? mix(audi, turn)
                        : audi != null ? audi : new RouteInfoElement[] { blank(), blank() };
                call(v, "setRouteInfo", new Class[] { out.getClass() }, new Object[] { out });
            }
            Object h = handler;
            if (h != null) {
                Object hv = field(h, "dsiKOMOView");
                Object cur = field(h, "routeInfoElements");
                if (hv != null && cur instanceof RouteInfoElement[]) {
                    call(hv, "setRouteInfo", new Class[] { cur.getClass() }, new Object[] { cur });
                }
            }
        } catch (Throwable t) {
            note("sending the current pair again failed: " + t);
        }
    }

    /* LOCK held */
    private static void push(String why) {
        try {
            destRefresh();
        } catch (Throwable t) {
            destInfo = null;
            note("working out the phone's arrival failed: " + t);
        }
        followFlag(why);
        cluster(why);
        showBox(why);
        int level = readLevel();
        boolean active = level > 0 && rgStatus == 1 && mainElement >= 0;
        if (!active && !sentActive) {
            return;                         /* nothing of ours is on the display */
        }
        Object h = findHandler();
        if (h == null) {
            return;
        }
        send(h, level, active, why);
    }

    /* LOCK held */
    private static void send(Object h, int level, boolean active, String why) {
        RouteInfoElement first = null;
        RouteInfoElement second = null;
        String back = "";
        try {
            if (active != sentActive) {
                call(h, "updateRgActive", new Class[] { Boolean.TYPE },
                        new Object[] { active ? Boolean.TRUE : Boolean.FALSE });
            }
            if (active) {
                first = follow();
                second = turn(level);
                RouteInfoElement[] pair = new RouteInfoElement[] { first, second };
                call(h, "setRouteInfo", new Class[] { pair.getClass() }, new Object[] { pair });
                ourPair = pair;
            } else {
                back = handBack(h);
            }
            sentActive = active;
            ++pushes;
        } catch (Throwable t) {
            note("handing the turn to the HUD handler failed: " + t);
            return;
        }
        String text = text(active);
        /* one line per manoeuvre, not per distance step: the log is small */
        String line = active
                ? "turn element " + mainElement + " direction " + direction
                        + " side streets " + (second.maneuverDescriptor.length - 1)
                        + ", road \"" + road + "\""
                : "cleared (" + back + ")";
        if (!line.equals(lastPush)) {
            lastPush = line;
            log("push " + pushes + " (" + why + "): " + line
                    + (active ? ", distance " + distValue + " unit " + distUnit + " (\"" + distanceText() + "\")" : "")
                    + "; " + text);
        }
        if (active) {
            String f = describe(first, false);
            if (!f.equals(lastFirst)) {
                lastFirst = f;
                log("first element (copy of the navigation's followInfoRIE): " + describe(first, true));
            }
        }
        String state = handlerState(h);
        if (!state.equals(lastState)) {
            lastState = state;
            log("HUD handler: " + state);
        }
    }

    /* The phone's guidance ended: let the navigation put its own pair back, as its updateKOMOFollowInfo() does. */
    private static String handBack(Object h) throws Throwable {
        ourPair = null;
        if (ext != null) {
            try {
                call(ext, "updateKOMOFollowInfo", new Class[0], new Object[0]);
                return "navigation's own pair restored";
            } catch (Throwable t) {
                note("updateKOMOFollowInfo() failed, sending a blank pair: " + t);
            }
        }
        RouteInfoElement[] pair = new RouteInfoElement[] { blank(), blank() };
        call(h, "setRouteInfo", new Class[] { pair.getClass() }, new Object[] { pair });
        ourPair = pair;
        return "blank pair";
    }

    /*
     * The text path. Stock (refreshDistanceToNextManeuver / refreshStreetMode): value in BAP tenths,
     * unit through convertBAP2KOMONavDistanceUnit, third argument "not showing the bar graph", street
     * only while the bar graph shows; without guidance -1 / 255 / false and "". The trial sends
     * distance and street together, to see which of them the display takes.
     */
    private static String text(boolean active) {
        Object c = hudCaller;
        if (c == null) {
            return "text path: no HUD caller";
        }
        long v = -1L;
        int u = 255;
        boolean valid = false;
        String r = "";
        if (active) {
            if (distValue >= 0) {
                v = distValue;
                u = navInfoUnit(distUnit);
                valid = true;
            }
            r = road;
        }
        try {
            call(c, "setDistanceToNextManeuver", new Class[] { Long.TYPE, Integer.TYPE, Boolean.TYPE },
                    new Object[] { new Long(v), new Integer(u), valid ? Boolean.TRUE : Boolean.FALSE });
            call(c, "setTurnToStreet", new Class[] { "".getClass(), "".getClass() }, new Object[] { r, "" });
            textValue = v;
            textUnit = u;
            textValid = valid;
            textRoad = r;
            textSent = active;
            return "text path: distance " + v + " unit " + u + " valid " + valid + ", street \"" + r + "\""
                    + (active ? " (phone bar graph " + bargraphOn + ")" : "");
        } catch (Throwable t) {
            note("the HUD text path failed: " + t);
            return "text path: failed";
        }
    }

    /* NaviClusterCommonExtension.convertBAP2KOMONavDistanceUnit of the stock code */
    private static int navInfoUnit(int bapUnit) {
        switch (bapUnit) {
            case 0: return 1;               /* m */
            case 1: case 6: return 2;       /* km */
            case 2: return 3;               /* yd */
            case 3: return 4;               /* ft */
            case 4: case 7: return 0;       /* mi */
            case 5: return 5;               /* quarter miles */
            default: return 255;
        }
    }

    /* The stock pair is { followInfoRIE, next manoeuvre }; updateNextManeuver() copies distanceToManeuver over. */
    private static RouteInfoElement follow() {
        RouteInfoElement e = null;
        try {
            Object f = ext != null ? field(ext, "followInfoRIE") : null;
            if (f instanceof RouteInfoElement) {
                e = copy((RouteInfoElement) f);
            }
        } catch (Throwable t) {
            e = null;
        }
        if (e == null) {
            e = blank();
        }
        e.distanceToManeuver = distValue >= 0 ? distanceText() : null;
        applyDest(e);
        return e;
    }

    /* The phone's arrival and remaining distance into a first element. Reads volatile fields only. */
    private static void applyDest(RouteInfoElement first) {
        int[] d = destInfo;
        if (d == null) {
            return;
        }
        if (d[2] != 2) {
            first.etaHours = d[0];
            first.etaMinutes = d[1];
            first.etaTimeFormat = d[2];
        } else {
            /* no time from the phone: "not available" as in the navigation's own empty element, not 0:00 */
            first.etaHours = 0;
            first.etaMinutes = 0;
            first.etaTimeFormat = 2;
        }
        if (d[3] >= 0) {
            first.distance = d[3];
            first.distanceFormat = d[4];
            first.distanceUnit = destUnitText;
            if (first.decimalMark == null) {
                first.decimalMark = decimalMark();
            }
        }
    }

    /*
     * The decimal mark of the HMI's language. Audi's own elements carry it (BAPDistance.getSeparator());
     * the JVM's locale is not the HMI's (the car showed "21.5 km" with German set, 2026-11-27).
     */
    private static String decimalMark() {
        String mark = audiDecimal;
        if (mark == null) {
            mark = ownDecimal;
        }
        return mark != null ? mark : ",";
    }

    /* LOCK held. Asks the navigation's distance formatter for the mark, once it is reachable. */
    private static void readDecimal() {
        if (ownDecimal != null) {
            return;
        }
        try {
            Object x = findExt();
            Object f = x != null ? field(x, "bapDistanceFormatter") : null;
            if (f == null) {
                return;
            }
            Object d = call(f, "formatDistanceToDestination", new Class[] { Integer.TYPE, Boolean.TYPE },
                    new Object[] { new Integer(21500), Boolean.FALSE });
            Object s = d != null ? call(d, "getSeparator", new Class[0], new Object[0]) : null;
            if (s instanceof String && ((String) s).length() > 0) {
                ownDecimal = (String) s;
                log("decimal mark from the navigation's formatter: \"" + s + "\"");
            }
        } catch (Throwable t) {
            note("reading the decimal mark failed: " + t);
        }
    }

    /* LOCK held. Works out the arrival and the remaining distance from what the phone sent last. */
    private static void destRefresh() {
        readDecimal();
        if (rgStatus != 1 || mainElement < 0 || (destSec <= 0L && destMeters <= 0)) {
            destInfo = null;
            return;
        }
        int[] d = new int[] { 0, 0, 2, -1, 255 };
        String unit = null;
        /*
         * 0 s with a few metres to go is "less than a minute": the arrival is now (CarPlay showed "11:18 Ankunft"
         * at 11:18 for 8 m, the box "0:00", A6, 2026-11-28). 0 s with a long way to go is the moment before the
         * phone has worked out its time.
         */
        if (destSec > 0L || (destSec == 0L && destMeters > 0 && destMeters <= 1000)) {
            long now = localNow();
            if (now > 0L) {
                Calendar c = new GregorianCalendar(TimeZone.getTimeZone("GMT"));
                c.setTime(new Date(now + destSec * 1000L));
                d[0] = c.get(Calendar.HOUR_OF_DAY);
                d[1] = c.get(Calendar.MINUTE);
                d[2] = timeFormat();
            }
        }
        if (destMeters > 0) {
            if (destUnit == 4 || destUnit == 5 || destUnit == 7) {
                long tenths = Math.round(destMeters / 160.9344);
                d[3] = (int) (tenths >= 1000L ? Math.round(destMeters / 1609.344) * 10L : Math.max(tenths, 1L));
                d[4] = 2;
                unit = "mi";
            } else if (destMeters < 1000) {
                d[3] = (int) (Math.round(destMeters / 10.0) * 100L);
                d[4] = 0;
                unit = "m";
            } else {
                long tenths = Math.round(destMeters / 100.0);
                d[3] = (int) (tenths >= 1000L ? Math.round(destMeters / 1000.0) * 10L : tenths);
                d[4] = 1;
                unit = "km";
            }
        }
        destUnitText = unit;
        destInfo = d;
        String line = d[2] != 2 ? "arrival " + d[0] + ":" + (d[1] < 10 ? "0" : "") + d[1] + " (format " + d[2] + ")"
                : "no arrival time";
        if (!line.equals(lastDest)) {
            lastDest = line;
            log("destination from the phone: " + line + ", " + destSec + " s and " + destMeters + " m to go -> distance "
                    + d[3] + " format " + d[4] + " " + unit);
        }
    }

    /* LOCK held. The car's local time in milliseconds, 0 when it is not known. */
    private static long localNow() {
        try {
            Object x = findExt();
            if (x == null) {
                return 0L;
            }
            Class[] none = new Class[0];
            Object[] no = new Object[0];
            Object sys = call(field(x, "navigationEnv"), "system", none, no);
            Object clock = call(sys, "clock", none, no);
            Object local = call(call(clock, "localTime", none, no), "get", none, no);
            int kind = local instanceof Long && ((Long) local).longValue() > 0L ? 2 : 1;
            if (clockLogged < kind) {
                clockLogged = kind;
                log("clock: localTime " + local + ", utcTime " + call(call(clock, "utcTime", none, no), "get", none, no)
                        + ", timeZone " + call(call(clock, "timeZone", none, no), "get", none, no) + ", adjusted "
                        + call(call(clock, "adjusted", none, no), "get", none, no));
            }
            if (!(local instanceof Long)) {
                return 0L;
            }
            long v = ((Long) local).longValue();
            if (v <= 0L) {
                return 0L;
            }
            return v < 100000000000L ? v * 1000L : v;       /* seconds, should the clock count those */
        } catch (Throwable t) {
            note("reading the car's clock failed: " + t);
            return 0L;
        }
    }

    /* 0 = 24 h, 1 = 12 h; as updateArrivalTime() of the stock code: unit value 10 is 24 h */
    private static int timeFormat() {
        try {
            Class[] none = new Class[0];
            Object[] no = new Object[0];
            Object sys = call(field(ext, "navigationEnv"), "system", none, no);
            Object setting = call(call(call(call(sys, "units", none, no), "timeFormat", none, no), "setting", none, no),
                    "get", none, no);
            Object value = call(setting, "getUnitValue", none, no);
            return value instanceof Integer && ((Integer) value).intValue() != 10 ? 1 : 0;
        } catch (Throwable t) {
            return 0;
        }
    }

    private static RouteInfoElement copy(RouteInfoElement from) throws Exception {
        RouteInfoElement e = new RouteInfoElement();
        Field[] f = from.getClass().getFields();
        for (int i = 0; i < f.length; ++i) {
            if (!Modifier.isStatic(f[i].getModifiers())) {
                f[i].set(e, f[i].get(from));
            }
        }
        return e;
    }

    private static RouteInfoElement blank() {
        RouteInfoElement e = new RouteInfoElement();
        e.trafficInfo = new TrafficInfo();
        e.signPostInfo = "";
        return e;
    }

    private static RouteInfoElement turn(int level) {
        RouteInfoElement e = blank();
        e.routeInfoElementType = RIE_MANEUVER;
        int sides = level >= 2 && sideStreets != null ? sideStreets.length : 0;
        ManeuverElement[] m = new ManeuverElement[1 + sides];
        m[0] = new ManeuverElement(mainElement, (short) direction, 0);
        for (int i = 0; i < sides; ++i) {
            m[1 + i] = new ManeuverElement(ELEMENT_SIDE_STREET, (short) (sideStreets[i] & 0xFF), 0);
        }
        e.maneuverDescriptor = m;
        e.elementIconIDs = new int[0];
        e.pOIElementNames = new String[0];
        e.prio1EventText = "";
        e.trafficDelayText = "";
        e.trafficInfo = null;               /* stock: none on a manoeuvre */
        e.streetIconID = -1;                /* stock: -1 = no road shield */
        e.exitIconId = -1;
        e.turnToStreet = road;
        e.signPostInfo = signPost;
        try {
            Object f = ext != null ? field(ext, "followInfoRIE") : null;
            if (f instanceof RouteInfoElement) {
                e.hourUnit = ((RouteInfoElement) f).hourUnit;
                e.minutesUnit = ((RouteInfoElement) f).minutesUnit;
                e.offroadText = ((RouteInfoElement) f).offroadText;
            }
        } catch (Throwable t) {
        }
        if (distValue >= 0) {
            String text = distanceText();
            e.distance = distValue;
            e.distanceFormat = komoUnit(distUnit);
            e.distanceToElement = text;
            e.distanceToManeuver = text;
            e.distanceUnit = unitText(distUnit);
        } else {
            /* FollowModeSceneUtils::format_distance: a negative value empties number, unit and "in" */
            e.distance = -1;
        }
        return e;
    }

    /* UnitConverter.convertBapDistanceUnitToKomoViewUnit of the stock code */
    private static int komoUnit(int bapUnit) {
        switch (bapUnit) {
            case 0: return 0;               /* m */
            case 1: case 6: return 1;       /* km */
            case 2: return 3;               /* yd */
            case 3: return 4;               /* ft */
            case 4: case 7: return 2;       /* mi */
            case 5: return 5;               /* quarter miles */
            default: return 255;
        }
    }

    private static String unitText(int bapUnit) {
        switch (bapUnit) {
            case 0: return "m";
            case 1: case 6: return "km";
            case 2: return "yd";
            case 3: return "ft";
            case 4: case 5: case 7: return "mi";
            default: return "";
        }
    }

    /* BAP sends tenths: 3000 m-tenths = "300 m", 12 km-tenths = "1,2 km" */
    private static String distanceText() {
        if (distValue < 0) {
            return "";
        }
        String unit = unitText(distUnit);
        int whole = distValue / 10;
        int tenth = distValue % 10;
        boolean small = distUnit == 0 || distUnit == 2 || distUnit == 3;
        if (small || tenth == 0) {
            return whole + " " + unit;
        }
        String mark = decimalMark();
        return whole + mark + tenth + " " + unit;
    }

    /* LOCK held. CombiBAPListener.clusterService is the NaviClusterCommonExtension. */
    private static Object findExt() {
        if (ext != null) {
            return ext;
        }
        try {
            Object listener = CombiBAPServiceNaviListenerWrapper.lastTarget;
            if (listener == null) {
                note("the navigation has not registered its cluster listener yet");
                return null;
            }
            Object x = field(listener, "clusterService");
            if (x == null) {
                note("no clusterService in " + listener.getClass().getName());
                return null;
            }
            ext = x;
            return x;
        } catch (Throwable t) {
            note("looking for the navigation's cluster extension failed: " + t);
            return null;
        }
    }

    /* LOCK held */
    private static Object findHandler() {
        if (handler != null) {
            return handler;
        }
        try {
            Object x = findExt();
            if (x == null) {
                return null;
            }
            Object h = call(x, "getMOSTHUDKDKHandler", new Class[0], new Object[0]);
            if (h == null) {
                note("this car has no head-up display handler in the navigation (" + x.getClass().getName()
                        + ".getMOSTHUDKDKHandler() is null: not coded for the HUD picture)");
                return null;
            }
            Object c = null;
            try {
                c = call(x, "getKomoCallerHUD", new Class[0], new Object[0]);
            } catch (Throwable t) {
                note("no HUD text path (getKomoCallerHUD): " + t);
            }
            hudCaller = c;
            handler = h;
            log("HUD handler found: " + h.getClass().getName() + ", text path "
                    + (c != null ? c.getClass().getName() : "MISSING"));
            return h;
        } catch (Throwable t) {
            note("looking for the HUD handler failed: " + t);
            return null;
        }
    }

    private static void startWatch() {
        synchronized (LOCK) {
            if (watching) {
                return;
            }
            watching = true;
        }
        try {
            Thread t = new Thread(new HudTurnFeed(null, "watch"), "HudTurnFeedWatch");
            t.setDaemon(true);
            /*
             * One below normal. At the lowest priority the first change of the cockpit's tab was answered after
             * five seconds while the unit was still starting (A6, 2026-11-28), the later ones within the second.
             */
            t.setPriority(Thread.NORM_PRIORITY - 1);
            t.start();
        } catch (Throwable t) {
            log("watcher not started: " + t);
        }
    }

    public void run() {
        for (;;) {
            try {
                synchronized (WAKE) {
                    if (!woken) {
                        WAKE.wait(WATCH_MS);    /* or sooner, when the cockpit's tab changed */
                    }
                    woken = false;
                }
            } catch (Throwable t) {
                return;
            }
            try {
                synchronized (LOCK) {
                    watch();
                }
            } catch (Throwable t) {
                note("watch failed: " + t);
            }
            try {
                hookLog();
            } catch (Throwable t) {
            }
        }
    }

    /*
     * LOCK held. What is in the handler and the HUD caller right now: ours, or the navigation's own
     * (written down as the reference, and replaced by ours while the phone guides and Audi does not).
     */
    static void watch() throws Throwable {
        if (komoOn()) {
            hookCluster();
        } else if (clusterProxy != null) {
            unhookCluster();
        }
        phoneWatch();
        if (followFlag("watch")) {
            tick();
            beat = 0;
        } else if (followState > 0 && ++beat >= BEAT_ROUNDS) {
            tickBox = boxIn(followState);
            /*
             * The hook acts only inside a setRouteInfo call: there it wakes a render engine that sleeps under
             * the follow scene and shows the scene again when the frame went away. A parked car sends none for
             * a long time, so the watcher sends the current pair every few seconds while the phone guides.
             */
            beat = 0;
            tick();
        }
        showBox("watch");
        watchBox();
        int level = readLevel();
        if (level == 0) {
            return;
        }
        Object h = findHandler();
        if (h == null) {
            return;
        }
        boolean audi = truth(ext, "rgActive");
        boolean ours = sentActive && rgStatus == 1 && mainElement >= 0;
        Object cur = field(h, "routeInfoElements");
        boolean pairOurs = cur == ourPair;
        Object c = hudCaller;
        long d = -1L;
        int u = 255;
        boolean v = false;
        String s = "";
        boolean textOurs = true;
        if (c != null) {
            d = ((Number) field(c, "distanceToNextManeuver")).longValue();
            u = ((Number) field(c, "distanceToNextManeuverUnit")).intValue();
            v = truth(c, "distanceToNextManeuverValidity");
            s = str(field(c, "turnToInfo"));
            textOurs = textSent && d == textValue && u == textUnit && v == textValid && s.equals(textRoad);
        }
        boolean again = ours && !audi;
        if (!pairOurs) {
            if (again) {
                ++replaced;
                if (replaced == 1 || replaced % 20 == 0) {
                    log("the navigation replaced our pair (" + replaced + " times so far) with " + describePair(cur, true)
                            + "; sending ours again");
                }
            } else {
                record(0, "navigation's pair" + (audi ? " (Audi guidance active)" : ""),
                        describePair(cur, false), describePair(cur, true));
            }
        }
        if (!textOurs) {
            if (again && textSent) {
                ++textReplaced;
                if (textReplaced == 1 || textReplaced % 20 == 0) {
                    log("the navigation replaced our text (" + textReplaced + " times so far) with distance " + d + " unit "
                            + u + " valid " + v + ", street \"" + s + "\"; sending ours again");
                }
            } else {
                String shape = "unit " + u + " valid " + v + ", turn to \"" + s + "\" sign \"" + str(field(c, "signPost"))
                        + "\", current street \"" + str(field(c, "currentStreet")) + "\", city \""
                        + str(field(c, "cityName")) + "\", rgMode " + field(c, "rgMode") + ", view enabled "
                        + field(c, "komoEnabled") + " visible " + field(c, "komoVisible") + "; navigation: rgActive " + audi
                        + " showBargraph " + truth(ext, "showBargraph") + " turnToStreetValid "
                        + truth(ext, "turnToStreetValid");
                record(1, "navigation's text" + (audi ? " (Audi guidance active)" : ""), shape, "distance " + d + " " + shape);
            }
        }
        if (again) {
            if (!pairOurs) {
                send(h, level, true, "watch");      /* sends the text as well */
            } else if (!textOurs) {
                text(true);
            }
        }
    }

    private static void record(int k, String label, String shape, String full) {
        long now = System.currentTimeMillis();
        synchronized (REC) {
            boolean kind = !shape.equals(recShape[k]);
            if (!kind && (full.equals(recFull[k]) || now - recTime[k] < QUIET_MS)) {
                return;
            }
            recShape[k] = shape;
            recFull[k] = full;
            recTime[k] = now;
        }
        log(label + ": " + full);
    }

    private static boolean truth(Object o, String name) {
        try {
            return o != null && Boolean.TRUE.equals(field(o, name));
        } catch (Throwable t) {
            return false;
        }
    }

    private static String str(Object o) {
        return o != null ? o.toString() : "";
    }

    private static String describePair(Object o, boolean full) {
        if (o == null) {
            return "null";
        }
        if (!(o instanceof Object[])) {
            return o.toString();
        }
        Object[] a = (Object[]) o;
        StringBuffer b = new StringBuffer();
        b.append(a.length).append(" element(s)");
        for (int i = 0; i < a.length; ++i) {
            b.append(" [").append(i).append("] ").append(describe(a[i], full));
        }
        return b.toString();
    }

    /* Every public field that is set; without the fields that count down when full is false. */
    private static String describe(Object e, boolean full) {
        if (e == null) {
            return "null";
        }
        StringBuffer b = new StringBuffer("{");
        try {
            Field[] f = e.getClass().getFields();
            for (int i = 0; i < f.length; ++i) {
                if (Modifier.isStatic(f[i].getModifiers())) {
                    continue;
                }
                String n = f[i].getName();
                if (!full && counts(n)) {
                    continue;
                }
                String s = show(f[i].get(e));
                if (s == null) {
                    continue;
                }
                if (b.length() > 1) {
                    b.append(", ");
                }
                b.append(n).append('=').append(s);
            }
        } catch (Throwable t) {
            b.append(" unreadable: ").append(t);
        }
        return b.append('}').toString();
    }

    private static boolean counts(String n) {
        return n.equals("distance") || n.equals("distanceToElement") || n.equals("distanceToManeuver")
                || n.equals("estimatedTimeToElement") || n.equals("estimatedTimeToManeuver")
                || n.equals("etaHours") || n.equals("etaMinutes")
                || n.equals("trafficDelayMinutes") || n.equals("trafficDelayText");
    }

    private static String show(Object v) {
        if (v == null) {
            return null;
        }
        if (v instanceof String) {
            return ((String) v).length() == 0 ? null : "\"" + v + "\"";
        }
        if (v instanceof Number) {
            return ((Number) v).longValue() == 0L ? null : v.toString();
        }
        if (v instanceof Boolean) {
            return ((Boolean) v).booleanValue() ? "true" : null;
        }
        if (v instanceof int[]) {
            int[] a = (int[]) v;
            if (a.length == 0) {
                return null;
            }
            StringBuffer b = new StringBuffer("[");
            for (int i = 0; i < a.length; ++i) {
                b.append(i > 0 ? "," : "").append(a[i]);
            }
            return b.append(']').toString();
        }
        if (v instanceof Object[]) {
            Object[] a = (Object[]) v;
            if (a.length == 0) {
                return null;
            }
            StringBuffer b = new StringBuffer("[");
            for (int i = 0; i < a.length; ++i) {
                b.append(i > 0 ? "," : "");
                b.append(a[i] instanceof String ? "\"" + a[i] + "\"" : describe(a[i], true));
            }
            return b.append(']').toString();
        }
        String d = describe(v, true);
        return "{}".equals(d) ? null : d;
    }

    private static String handlerState(Object h) {
        try {
            return "view service " + (field(h, "dsiKOMOView") != null ? "set" : "MISSING")
                    + ", hudSetting " + field(h, "hudSetting")
                    + ", gfxAvailable " + field(h, "gfxAvailable")
                    + ", komoViewEnabled " + field(h, "komoViewEnabled")
                    + ", komoViewVisible " + field(h, "komoViewVisible")
                    + ", rgActive " + field(h, "rgActive")
                    + ", data rate " + field(h, "currentDataRate") + " (asked " + field(h, "requestedDataRate") + ")";
        } catch (Throwable t) {
            return "state not readable: " + t;
        }
    }

    /* a field that tells something extra: "?" where a build does not have it */
    private static Object opt(Object o, String name) {
        try {
            return field(o, name);
        } catch (Throwable t) {
            return "?";
        }
    }

    private static Object field(Object o, String name) throws Exception {
        for (Class c = o.getClass(); c != null; c = c.getSuperclass()) {
            Field f;
            try {
                f = c.getDeclaredField(name);
            } catch (NoSuchFieldException e) {
                continue;
            }
            f.setAccessible(true);
            return f.get(o);
        }
        throw new NoSuchFieldException(name);
    }

    private static void setField(Object o, String name, Object value) throws Exception {
        for (Class c = o.getClass(); c != null; c = c.getSuperclass()) {
            Field f;
            try {
                f = c.getDeclaredField(name);
            } catch (NoSuchFieldException e) {
                continue;
            }
            f.setAccessible(true);
            f.set(o, value);
            return;
        }
        throw new NoSuchFieldException(name);
    }

    private static Object call(Object o, String name, Class[] types, Object[] args) throws Throwable {
        Method m = o.getClass().getMethod(name, types);
        m.setAccessible(true);
        try {
            return m.invoke(o, args);
        } catch (InvocationTargetException e) {
            throw e.getTargetException();
        }
    }

    /* 0 = off (no marker), 1 = main arrow, 2 = with side streets; an empty marker counts as 1 */
    private static int readLevel() {
        FileInputStream in = null;
        try {
            File f = new File(MARKER);
            if (!f.exists()) {
                return 0;
            }
            in = new FileInputStream(f);
            int c = in.read();
            return c == '2' ? 2 : (c == '0' ? 0 : 1);
        } catch (Throwable t) {
            return 0;
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (Throwable t) {
                }
            }
        }
    }

    private static void note(String text) {
        synchronized (HudTurnFeed.class) {
            if (text.equals(lastNote)) {
                return;
            }
            lastNote = text;
        }
        log(text);
    }

    /**
     * The hook's log is in RAM and gone with the next start; its new lines are
     * copied into this log, which the ModKit takes to the card. Whole lines
     * only, at most 4096 bytes per round (the hook stops after 400 lines).
     */
    static void hookLog() {
        File f = new File(HOOK_LOG);
        long len = f.length();
        if (len < hookLogAt) {
            hookLogAt = 0;
        }
        if (len == hookLogAt) {
            return;
        }
        FileInputStream in = null;
        try {
            in = new FileInputStream(f);
            long skipped = 0;
            while (skipped < hookLogAt) {
                long n = in.skip(hookLogAt - skipped);
                if (n <= 0) {
                    return;
                }
                skipped += n;
            }
            byte[] buf = new byte[(int) Math.min(len - hookLogAt, 4096L)];
            int got = 0;
            while (got < buf.length) {
                int n = in.read(buf, got, buf.length - got);
                if (n < 0) {
                    break;
                }
                got += n;
            }
            int end = got;
            while (end > 0 && buf[end - 1] != '\n') {
                end--;
            }
            if (end == 0) {
                if (got == 4096) {
                    hookLogAt += got;   // one line longer than the buffer: not ours, skip it
                }
                return;
            }
            hookLogAt += end;
            String text = new String(buf, 0, end);
            int from = 0;
            while (from < text.length()) {
                int nl = text.indexOf('\n', from);
                if (nl < 0) {
                    break;
                }
                if (nl > from) {
                    log("navigation hook: " + text.substring(from, nl));
                }
                from = nl + 1;
            }
        } catch (Throwable t) {
        } finally {
            if (in != null) {
                try {
                    in.close();
                } catch (Throwable t) {
                }
            }
        }
    }

    private static void log(String line) {
        String text = System.currentTimeMillis() / 1000L + " s  " + line + "\n";
        synchronized (HudTurnFeed.class) {
            String path = new File(LOG_DIR).isDirectory() ? LOG_MAIN : LOG_TMP;
            FileOutputStream out = null;
            try {
                File f = new File(path);
                if (f.length() > LOG_LIMIT) {
                    File old = new File(path + ".old");
                    old.delete();
                    f.renameTo(old);
                }
                out = new FileOutputStream(path, true);
                out.write(text.getBytes());
            } catch (Throwable t) {
            } finally {
                if (out != null) {
                    try {
                        out.close();
                    } catch (Throwable t) {
                    }
                }
            }
        }
    }
}
