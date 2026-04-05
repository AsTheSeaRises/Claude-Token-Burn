import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private let viewModel = TokenBurnViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon — menu bar agent only
        NSApp.setActivationPolicy(.accessory)
        NotificationManager.shared.requestAuthorization()

        viewModel.onUpdate = { [weak self] in self?.refreshStatusItem() }
        viewModel.onOpenSettings = { [weak self] in
            self?.closePopover()
            self?.openSettings()
        }

        setupStatusItem()
        setupPopover()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.action = #selector(handleStatusItemClick)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refreshStatusItem()
    }

    func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let pct   = viewModel.sessionPercentRemaining
        let color = Constants.tokenColor(percentRemaining: pct)
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        ]
        let str = NSMutableAttributedString()
        let iconName = viewModel.selectedProvider.iconName
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            img.isTemplate = false
            let tinted = img.copy() as! NSImage
            tinted.lockFocus()
            color.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            let attachment = NSTextAttachment()
            attachment.image = tinted
            str.append(NSAttributedString(attachment: attachment))
            str.append(NSAttributedString(string: " "))
        }
        str.append(NSAttributedString(string: viewModel.statusBarLabel, attributes: attrs))
        button.attributedTitle = str
    }

    @objc private func handleStatusItemClick() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Settings…",   action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Popover

    private func setupPopover() {
        let dropdownView = DropdownView(
            viewModel: viewModel,
            onSettingsTap: { [weak self] in
                self?.closePopover()
                self?.openSettings()
            }
        )

        let controller = NSHostingController(rootView: dropdownView)
        let pop = NSPopover()
        pop.contentSize     = NSSize(width: 300, height: 440)
        pop.behavior        = .transient
        pop.contentViewController = controller
        self.popover = pop
    }

    @objc func togglePopover() {
        guard let pop = popover else { return }
        if pop.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem?.button else { return }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    // MARK: - Settings Window

    @objc func openSettings() {
        if let win = settingsWindow, win.isVisible {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(onDone: { [weak self] in
            self?.settingsWindow?.close()
        })
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Token Burn — Settings"
        win.contentViewController = NSHostingController(rootView: settingsView)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = win
    }

    @objc func refreshNow() {
        viewModel.refresh()
    }
}
