//
//  XMPPStream+Parser.swift
//  XMPPChatCore
//

import Foundation

// MARK: - XMPP Stanza Parser
internal class XMPPStanzaParser {
    static func parse(_ xmlString: String) -> XMPPStanza? {
        guard let data = xmlString.data(using: .utf8) else {
            //print("⚠️ Failed to convert XML string to data")
            return nil
        }
        
        // Clean up XML string if needed
        // Some servers send multiple stanzas in one WebSocket frame
        // Our simplified parser handles one at a time
        
        let delegate = XMPPStanzaParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        
        if !parser.parse() {
            // //NSlog("⚠️ XML Parse Error: %@", parser.parserError?.localizedDescription ?? "Unknown error")
            //print("⚠️ XML Parse Error: \(parser.parserError?.localizedDescription ?? "Unknown error")")
            if let error = parser.parserError {
                //print("   Error domain: \(error._domain), code: \(error._code)")
            }
        }
        
        return delegate.rootStanza
    }
}

internal class XMPPStanzaParserDelegate: NSObject, XMLParserDelegate {
    var rootStanza: XMPPStanza?
    private var stack: [XMPPStanza] = []
    private var currentText: String = ""
    private var parseError: Error?
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        // Save any accumulated text to the previous element
        if !stack.isEmpty && !currentText.isEmpty {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let lastIndex = stack.count - 1
                var last = stack[lastIndex]
                last.text = (last.text ?? "") + trimmed
                stack[lastIndex] = last
            }
        }
        currentText = ""
        
        let stanza = XMPPStanza(name: elementName, attributes: attributeDict)
        
        if stack.isEmpty {
            rootStanza = stanza
            stack.append(stanza)
        } else {
            // Add as child to current parent
            let parentIndex = stack.count - 1
            var parent = stack[parentIndex]
            
            // We need to update the parent in the stack after modifying its children
            // but we'll do that by updating the parent's child list after the child is complete
            // For now, just keep track of the parent-child relationship
            
            // Push new element onto stack
            stack.append(stanza)
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        // Save accumulated text to current element
        if !stack.isEmpty && !currentText.isEmpty {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let lastIndex = stack.count - 1
                var last = stack[lastIndex]
                last.text = (last.text ?? "") + trimmed
                stack[lastIndex] = last
            }
        }
        currentText = ""
        
        if let completed = stack.popLast() {
            if let parentIndex = stack.lastIndex(where: { _ in true }) {
                var parent = stack[parentIndex]
                parent.children.append(completed)
                stack[parentIndex] = parent
                
                // If this parent is the root, update it
                if parentIndex == 0 {
                    rootStanza = parent
                }
            } else {
                // Root element finished
                rootStanza = completed
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
        // NSlog("❌ XML Parser Error: %@", parseError.localizedDescription)
        // print("❌ XML Parser Error: \(parseError.localizedDescription)")
    }
    
    func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
        //print("⚠️ XML Validation Error: \(validationError.localizedDescription)")
    }
}
