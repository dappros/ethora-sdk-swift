//
//  XMPPStanza.swift
//  XMPPChatCore
//
//  XMPP Stanza representation
//

import Foundation

public struct XMPPStanza {
    public let name: String
    public var attributes: [String: String]
    public var children: [XMPPStanza]
    public var text: String?
    
    public init(
        name: String,
        attributes: [String: String] = [:],
        children: [XMPPStanza] = [],
        text: String? = nil
    ) {
        self.name = name
        self.attributes = attributes
        self.children = children
        self.text = text
    }
    
    public func getChild(_ name: String) -> XMPPStanza? {
        return children.first { $0.name == name }
    }
    
    public func getChild(_ name: String, xmlns: String? = nil) -> XMPPStanza? {
        return children.first { child in
            guard child.name == name else { return false }
            if let xmlns = xmlns {
                return child.attributes["xmlns"] == xmlns
            }
            return true
        }
    }
    
    public func getChildren(_ name: String) -> [XMPPStanza] {
        return children.filter { $0.name == name }
    }
    
    public func getChildText(_ name: String) -> String? {
        return getChild(name)?.text
    }
    
    public func toXML() -> String {
        var xml = "<\(name)"
        for (key, value) in attributes {
            xml += " \(key)=\"\(value.escapeXML())\""
        }
        
        if children.isEmpty && text == nil {
            xml += "/>"
        } else {
            xml += ">"
            if let text = text {
                xml += text.escapeXML()
            }
            for child in children {
                xml += child.toXML()
            }
            xml += "</\(name)>"
        }
        return xml
    }
}

extension String {
    func escapeXML() -> String {
        return self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

