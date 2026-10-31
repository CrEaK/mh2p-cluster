/*
 * Hides the Audi map's zoom scale (magnifier or auto-zoom icon, "400 m",
 * scale bar) in the cockpit while the CarPlay cluster video is shown; it
 * belongs to the hidden Audi map and is meaningless over the phone's map.
 *
 * HandCodedMapWidgetFactory.createMapZoomGroupCombi builds the group as a
 * layout container of three widgets, the label bound to model 403861
 * (ZoomViewFPKRevo's magnification). The status bar is rendered into a
 * subtexture (SubframeController) that the cluster places itself, so neither
 * the display contexts nor the opacity of the FPK layer 41 reach it (tested
 * 2026-10-31). The group is found by walking the widget trees of the current
 * screens of every terminal and switched with setVisibleByDisclaimer, a
 * visibility bit the stock HMI does not use on these widgets; the enclosing
 * subframe is then invalidated so the subtexture is drawn again. The file
 * /mnt/app/eso/bin/apps/cluster/altscreen_zoom_scale keeps the scale shown.
 */
package de.eso.hmiservice.display;

import de.audi.atip.hmi.HMIService;
import de.audi.atip.hmi.IRootWindow;
import de.audi.atip.hmi.view.HMIView;
import de.audi.atip.hmi.view.Screen;
import de.eso.widgets.controllers.AbstractWidget;
import de.eso.widgets.subframe.SubframeController;
import java.util.List;
import java.util.Vector;

final class ZoomScaleHider {
    private static final int MODEL_ZOOM_SCALE = 403861;
    private static final int TERMINALS = 10;
    private static final long WALK_MS = 5000L;
    private static final String SHOW_FLAG = "/mnt/app/eso/bin/apps/cluster/altscreen_zoom_scale";

    private static Vector groups = new Vector();
    private static long lastWalk;
    private static int lastFound = -1;
    private static boolean lastHide;

    private ZoomScaleHider() {
    }

    /* returns a line to log when the state or the widgets found changed */
    static synchronized String apply(HMIService hmi, boolean video) {
        boolean hide = video && !new java.io.File(SHOW_FLAG).exists();
        String msg = null;
        long now = System.currentTimeMillis();
        if (hide && (groups.isEmpty() || now - lastWalk >= WALK_MS)) {
            lastWalk = now;
            int[] walked = new int[1];
            Vector found = new Vector();
            StringBuffer where = new StringBuffer();
            for (int t = 0; t < TERMINALS; ++t) {
                try {
                    IRootWindow root = hmi.getRootWindow(t);
                    if (root == null) {
                        continue;
                    }
                    collectScreen(root.getCurrentScreen(t), t, found, walked, where);
                    collectScreen(root.getCurrentMainScreen(t), t, found, walked, where);
                    collectScreen(root.getCurrentPopupScreen(t), t, found, walked, where);
                }
                catch (Throwable e) {
                    where.append(' ').append(t).append(":!").append(e.getClass().getName());
                }
            }
            for (int i = 0; i < groups.size(); ++i) {
                if (!found.contains(groups.elementAt(i))) {
                    setVisible((AbstractWidget)groups.elementAt(i), true);
                }
            }
            groups = found;
            if (found.size() != lastFound) {
                lastFound = found.size();
                msg = "zoom scale: " + found.size() + " group(s) found, " + walked[0]
                        + " widgets walked, screens" + where;
            }
        }
        boolean changed = false;
        for (int i = 0; i < groups.size(); ++i) {
            changed |= setVisible((AbstractWidget)groups.elementAt(i), !hide);
        }
        if (changed) {
            for (int t = 0; t < TERMINALS; ++t) {
                try {
                    IRootWindow root = hmi.getRootWindow(t);
                    if (root != null) {
                        root.triggerRepaint();
                    }
                }
                catch (Throwable e) {
                }
            }
        }
        if (hide != lastHide) {
            lastHide = hide;
            String state = "zoom scale " + (hide ? "hidden" : "shown") + " (" + groups.size() + " group(s))";
            msg = msg == null ? state : msg + "; " + state;
        }
        return msg;
    }

    private static void collectScreen(Screen screen, int terminal, Vector found, int[] walked, StringBuffer where) {
        if (screen == null) {
            return;
        }
        where.append(' ').append(terminal).append(':').append(screen.getID());
        collectViews(screen.getViews(), found, walked);
        HMIView[][] replacements = screen.getReplacementWidgets();
        if (replacements != null) {
            for (int i = 0; i < replacements.length; ++i) {
                collectViews(replacements[i], found, walked);
            }
        }
    }

    private static void collectViews(HMIView[] views, Vector found, int[] walked) {
        if (views == null) {
            return;
        }
        for (int i = 0; i < views.length; ++i) {
            if (views[i] instanceof AbstractWidget) {
                collect((AbstractWidget)views[i], found, walked, 0);
            }
        }
    }

    private static void collect(AbstractWidget w, Vector found, int[] walked, int depth) {
        ++walked[0];
        if (w.getModelID() == MODEL_ZOOM_SCALE && w.getParent() instanceof AbstractWidget) {
            Object group = w.getParent();
            if (!found.contains(group)) {
                found.addElement(group);
            }
        }
        if (depth > 40) {
            return;
        }
        List children = w.getChildren();
        if (children == null) {
            return;
        }
        for (int i = 0; i < children.size(); ++i) {
            Object c = children.get(i);
            if (c instanceof AbstractWidget) {
                collect((AbstractWidget)c, found, walked, depth + 1);
            }
        }
    }

    /* returns true when the visibility changed */
    private static boolean setVisible(AbstractWidget group, boolean visible) {
        if (group.isVisibleByDisclaimer() == visible) {
            return false;
        }
        group.setVisibleByDisclaimer(visible);
        for (Object p = group.getParent(); p instanceof AbstractWidget; p = ((AbstractWidget)p).getParent()) {
            if (p instanceof SubframeController) {
                ((SubframeController)p).setInvalid(true);
                break;
            }
        }
        return true;
    }
}
