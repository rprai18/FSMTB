# Deploy Apex and LWC with package-apex-lwc.xml

This manifest deploys all Apex classes, the Account trigger, and all Lightning Web Components in this project.

## Deploy to default org

```bash
sf project deploy start --manifest manifest/package-apex-lwc.xml
```

## Deploy to a specific org (alias)

```bash
sf project deploy start --manifest manifest/package-apex-lwc.xml --target-org YOUR_ORG_ALIAS
```

## What’s included

- **ApexClass** – 35 classes (controllers, services, batch, handlers)
- **ApexTrigger** – AccountTrigger (and its handler is in ApexClass)
- **LightningComponentBundle** – 34 LWC components

**Note:** Trigger handler `AccountTriggerHandler` is deployed as part of ApexClass. Deploy this manifest from the project root (`FSMTDev`).
