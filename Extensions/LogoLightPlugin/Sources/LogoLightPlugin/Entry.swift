import LogoLightHost

@_cdecl("statusdeck_plugin_create")
public func statusdeckPluginCreate() -> UnsafeMutableRawPointer { MyStatusLogoPlugin.make() }
