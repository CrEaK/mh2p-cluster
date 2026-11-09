/*
 * Copyright (c) 2026 CrEaK (https://github.com/CrEaK)
 *
 * Licensed under CC BY-NC-SA 4.0
 * https://creativecommons.org/licenses/by-nc-sa/4.0/
 * NOT FOR COMMERCIAL USE
 */
package de.audi.app.terminalmode.smartphone.androidauto2.nav;

import de.audi.app.terminalmode.smartphone.carplay.CarPlayClusterIntegration;

/**
 * Decides whether the cockpit shows the CarPlay map, in altscreen mode.
 *
 * The shipped CarPlayClusterIntegration starts the cockpit picture when
 * CarPlay takes the MMI screen and stops it when the MMI takes it back
 * (radio, reverse camera, Audi menus). The phone keeps sending the cockpit
 * video in those moments (A6, 2026-11-09: frames went on while the MMI
 * showed the radio), so the cockpit can keep the CarPlay map.
 *
 * Instead of the real screen owner, this thread hands the integration
 * DEVICE while the "Carplay Map" setting is on and the hook's cockpit video
 * runs, MAINUNIT otherwise. The integration then sends "start"/"stop" to the
 * cluster daemon as before, and KombiMapGuard switches the cockpit display
 * as before. The real owner is only logged. Once a second, or at once when
 * the menu changes the setting.
 *
 * Java 1.4 source level. Never throws out of its methods.
 */
public final class CarPlayMapSwitch implements Runnable {

    private static final int RESOURCE_MAIN_SCREEN = 1;
    private static final int OWNER_MAINUNIT = 1;
    private static final int OWNER_DEVICE = 2;
    private static final long TICK_MS = 1000L;

    private final CarPlayClusterIntegration integration;
    private volatile int owner;
    private boolean applied;
    private boolean lastVideo;
    private boolean lastEnabled;
    private boolean first = true;

    private CarPlayMapSwitch(CarPlayClusterIntegration integration) {
        this.integration = integration;
    }

    /** Starts the thread; returns null when it could not be started. */
    public static CarPlayMapSwitch start(CarPlayClusterIntegration integration) {
        CarPlayMapSetting.setLogTarget(integration);
        try {
            CarPlayMapSwitch s = new CarPlayMapSwitch(integration);
            Thread t = new Thread(s, "CarPlayMapSwitch");
            t.setDaemon(true);
            /* NORM_PRIORITY for the same reason as KombiMapGuard: a lower
             * priority thread gets no CPU while the HMI starts up. */
            t.setPriority(Thread.NORM_PRIORITY);
            t.start();
            return s;
        } catch (Throwable t) {
            CarPlayMapSetting.log("Carplay Map: switch not started, the MMI screen owner decides: " + t);
            return null;
        }
    }

    /** The real MMI screen owner from DSI; only logged. */
    public void ownerChanged(int newOwner) {
        if (newOwner != OWNER_MAINUNIT && newOwner != OWNER_DEVICE) {
            return;
        }
        if (newOwner == owner) {
            return;
        }
        owner = newOwner;
        CarPlayMapSetting.log("Carplay Map: MMI screen owner " + ownerName(newOwner)
                + ", cockpit follows the setting (" + (CarPlayMapSetting.isEnabled() ? "on" : "off") + ")");
    }

    public void run() {
        CarPlayMapSetting.log("Carplay Map: switch started, setting " + (CarPlayMapSetting.isEnabled() ? "on" : "off"));
        while (true) {
            try {
                tick();
            } catch (Throwable t) {
                CarPlayMapSetting.log("Carplay Map: tick error: " + t);
            }
            CarPlayMapSetting.await(TICK_MS);
        }
    }

    private void tick() {
        boolean video = CarPlayMapSetting.isConnected();
        boolean enabled = CarPlayMapSetting.isEnabled();
        if (first || video != lastVideo) {
            lastVideo = video;
            CarPlayMapSetting.fireMenu();
        }
        boolean want = enabled && video;
        if (first || want != applied || enabled != lastEnabled) {
            first = false;
            lastEnabled = enabled;
            boolean change = want != applied;
            applied = want;
            CarPlayMapSetting.log("Carplay Map: cockpit " + (want ? "CarPlay map" : "Audi map")
                    + " (setting " + (enabled ? "on" : "off") + ", cockpit video " + (video ? "running" : "stopped")
                    + ", MMI screen owner " + ownerName(owner) + ")");
            if (change) {
                integration.onResourceChanged(RESOURCE_MAIN_SCREEN, want ? OWNER_DEVICE : OWNER_MAINUNIT);
            }
        }
    }

    private static String ownerName(int o) {
        if (o == OWNER_DEVICE) {
            return "DEVICE";
        }
        if (o == OWNER_MAINUNIT) {
            return "MAINUNIT";
        }
        return "unknown";
    }
}
