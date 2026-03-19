# How Ethora Built and Published Its Chat Component on npm.js

At Ethora, we have always seen modular chat developing experiences as a core of our technological vision. We've been working on it, expanded our platform, and realized that a flexible, production-ready component can be a great advantage. Just a simple, reliable, scalable plug-and-play set that can be embedded directly into JavaScript environments. So, we engineered a chat component on npm.js that you can integrate into any application.

In this article, we'll guide you through the entire process of planning and building this developer's package, specifically designed for optimal performance when creating communication tools.

## Why and How We Created Our NPM Chat Package

The initial idea is simple: you don't have to reinvent the messaging UI every time you launch a product. We decided to create an npm package and extracted it from Ethora engine, ensuring it's suitable for JavaScript and React developers. Put simply, it's a simplified and faster version of Ethora.

We also realized that the npm package for chat integration should adapt to any backend structures, authentication approaches, and UI customization requirements. This simplicity and extensibility became the foundation of the project.

Ethora's npm package includes:

- **UI Components**
- **Global State Store (Redux)**
- **XMPP Protocol Integration**
- **Networking Logic & Configuration**

Additionally, unlike a GitHub repository, the chat component doesn't require manual setup or dependency handling and can be integrated instantly as a single module. So, if you're building an app from scratch, you can use the SDK, but if you need to integrate a chat into your application, it's easier and faster to use npm component.

### Planning and Design Considerations

Before writing the first line of code, we defined clear goals:

- The component must offer production-ready stability
- It must remain lightweight and modular
- It should be fully customizable for different branding requirements
- It must seamlessly integrate with WebSocket- or API-driven messaging backends

Additionally, we explored problems developers typically face when integrating interfaces and understood that the most common ones are performance bottlenecks, high rendering costs, and the need for scalable state management. This knowledge helped us create a clear architectural blueprint that balanced usability with technical robustness.

### Setting Up the Development Environment

To establish the foundation for package development, we prepared a project structure, using TypeScript and Rollup for bundling. A critical part here was to ensure that we could set up npm package logic clearly, with scripts dedicated to building, linting, and testing.

How we set up the npm package and created package.json.

## Developing and Customizing the Chat Component

When the first steps were completed, it was time to implement the library. We needed to create an npm chat module that adhered to best practices in UI architecture, while ensuring that developers have full control over customization. That's why features like message list, input bar, typing indicators, and others in Ethora are independent units. Thus, developers can override styles, inject extensions, or modify behaviors.

Moreover, we also introduced a custom chat npm package setup for those who need even more control. This allowed teams to extend the package while staying aligned with Ethora's core updates.

## Publishing and Managing Our Package

To check the library's readiness for real-world use, we tested compatibility across multiple frameworks, validated bundling outputs, and ensured that tree-shaking worked properly. When everything was ready, we proceeded to publish the npm package, paying careful attention to versioning and semantic-release strategies.

Over time, the package evolved into a versatile chat app npm package, supporting public releases for open-source components and internal versions for company-specific needs. For enterprise projects requiring confidentiality, we created workflows that allowed teams to create private npm package variants.

### Publishing Process and Version Control

For publishing, we enhanced standard npm best practices with automation. We implemented CI/CD pipelines that performed lint checks, unit tests, build validation, and changelog generation before initiating the final step to deploy npm chat module updates.

Versioning was managed with semantic rules, ensuring that breaking changes, new features, and patches were clearly communicated through version increments.

### Benefits of Private vs Public Packages

When you're deciding which package to choose, you need to focus on what you're building and decide based on your needs. Public packages are perfect for community collaboration, rapid feedback, and wide adoption.

But enterprises usually choose private packages, first of all, because they ensure complete privacy and compliance. Also, they provide them with flexibility, allowing them to fully tailor the chat component to their systems. Ethora supports both options, providing an adaptable solution whether you need openness or confidentiality.

## Integrating the Chat Component into Applications

After publishing, the next step was validating real-world integrations. Thanks to the modular architecture, npm.js chat integration works seamlessly with both small web apps and large enterprise platforms.

The package supports custom themes, message rendering logic, and dynamic configuration, making it suitable for varied use cases, from social networking to customer support tools. Documentation and code examples further simplify setup, ensuring a streamlined onboarding experience.

## Conclusion

Building our npm.js chat component has been an exciting journey and has contributed to modular architecture, usability design, and open distribution. We share our experience to encourage developers to explore reusable packages and build new tools for the JavaScript ecosystem. Such instruments make the development process easier: you can create solutions faster, without sacrificing the ability to tailor them to your needs. Try how it works with Ethora.
