//
//  SwitchView.swift
//  XMPPChatUI
//
//  Toggle switch component
//

import SwiftUI

public struct SwitchView: View {
    @Binding var isOn: Bool
    let onColor: Color
    let offColor: Color
    
    public init(
        isOn: Binding<Bool>,
        onColor: Color = .blue,
        offColor: Color = .gray
    ) {
        self._isOn = isOn
        self.onColor = onColor
        self.offColor = offColor
    }
    
    public var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(CustomToggleStyle(onColor: onColor, offColor: offColor))
    }
}

struct CustomToggleStyle: ToggleStyle {
    let onColor: Color
    let offColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(configuration.isOn ? onColor : offColor)
                    .frame(width: 50, height: 30)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: 26, height: 26)
                    .padding(2)
                    .offset(x: configuration.isOn ? 10 : -10)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}
