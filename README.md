<p align="center">
  <img src="screenshots/icon-dark.png" width="128" height="128" alt="Mint Leaf Icon">
</p>

<h1 align="center">Mint Leaf</h1>

<p align="center">
  <strong>Your personal finance companion.</strong><br>
  Track spending, set budgets, forecast your finances, and stay in control.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-3.0.0-gold" alt="Version">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20iOS-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-6.0-orange" alt="Swift">
  <img src="https://img.shields.io/badge/swiftui-5.0-purple" alt="SwiftUI">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<p align="center">
  <a href="https://github.com/Kolomaster68/mint-leaf/releases/latest">
    <img src="https://img.shields.io/badge/Download-DMG-brightgreen?style=for-the-badge&logo=apple" alt="Download DMG">
  </a>
</p>

## Star History

<a href="https://www.star-history.com/?repos=Kolomaster68%2Fmint-leaf&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=Kolomaster68/mint-leaf&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=Kolomaster68/mint-leaf&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=Kolomaster68/mint-leaf&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <img src="screenshots/dashboard-light.png" width="800" alt="Mint Leaf Dashboard">
</p>

## What's New in v3.0

v3.0 is the biggest update to Mint Leaf yet, adding five major features and a suite of quality-of-life improvements.

### New Features

- **Net Worth Tracker** — See your total net worth over time with an interactive chart, asset/liability breakdown, and per-account detail
- **Reports** — Monthly and yearly financial reports with income/expense summaries, category pie charts, top merchant tables, and CSV export
- **Goals & Wishlist** — Set savings goals with progress tracking, target dates, and daily savings calculations. Wishlist mode lets you track items you want to buy with links and purchase status
- **Forecast** — Balance projections for 30/60/90 days or 6 months based on scheduled transactions, with what-if scenarios and runway calculations
- **Tags** — Label transactions across categories with colour-coded tags. Tag from the transaction editor, view tagged transactions in the Tags panel, and filter spending by tag

### Improvements

- **Transfer Fix** — Transfers between accounts no longer inflate income and expense totals
- **XLSX Import Fix** — Files with title rows before column headers now import correctly
- **Balance Chart Fix** — Resolved looping artifacts and inverted area shading on the balance trend chart
- **Swipe-to-Dismiss Notifications** — Dismiss alerts with a swipe; restore them anytime from the toolbar
- **Persistent Notification State** — Dismissed notifications stay dismissed across app restarts
- **Tag Picker in Transaction Editor** — Add or remove tags when creating or editing any transaction
- **Streamlined Trends** — Category breakdown moved to Reports to reduce redundancy

## Features

### Accounts & Transactions
- **Multiple Accounts** — Track checking, savings, credit cards, and cash with live balances
- **Transaction Inbox** — Review and categorise uncategorised transactions in one place
- **Powerful Search** — Find transactions by name, category, account, notes, or amount with filters
- **Multi-Currency** — Support for 39 currencies with automatic formatting and per-account currency
- **CSV, XLSX & PDF Import** — Import bank statements from CSV, Excel, or PDF documents
- **Reconciliation** — Mark transactions as reconciled and compare against bank statements

### Budgets & Planning
- **Budgets** — Set monthly spending limits by category and track progress in real time
- **Goals & Wishlist** — Savings targets with progress rings, target dates, and daily savings needed. Wishlist mode for tracking items to buy
- **Forecast** — Balance projections based on scheduled transactions with what-if scenarios
- **Scheduled Transactions** — Manage recurring bills, subscriptions, and income on a calendar
- **Subscription Calendar** — Visual calendar view of all subscriptions with pause/resume controls

### Analytics
- **Trends** — Visualise spending, income vs expense, and balance over time with interactive charts
- **Smart Insights** — Cashflow forecasts, anomaly detection, and spending summaries
- **Net Worth** — Historical net worth chart with asset/liability breakdown
- **Reports** — Monthly and yearly reports with category pie charts, top merchants, and CSV export

### Organisation
- **Tags** — Colour-coded labels that work across categories for flexible transaction grouping
- **Rules & Automation** — Auto-categorise transactions with pattern matching and merchant aliases
- **Notification Centre** — In-app alerts for due bills, exceeded budgets, and overdue items with swipe-to-dismiss

### Privacy & Customisation
- **Privacy First** — All data stays on your device. No accounts, no cloud, no tracking
- **Light & Dark Mode** — Full support with custom app icons for each appearance
- **Keyboard Shortcuts** — Full keyboard navigation for power users
- **Interactive Tutorial** — Guided walkthrough with sample data to learn the app

## Screenshots

### Light Mode

<table>
  <tr>
    <td align="center"><img src="screenshots/dashboard-light.png" width="400" alt="Overview Dashboard"><br><strong>Overview Dashboard</strong></td>
    <td align="center"><img src="screenshots/tutorial-search-light.png" width="400" alt="Search"><br><strong>Search</strong></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/inbox-light.png" width="400" alt="Transaction Inbox"><br><strong>Transaction Inbox</strong></td>
    <td align="center"><img src="screenshots/budgets-light.png" width="400" alt="Budgets"><br><strong>Budgets</strong></td>
  </tr>
</table>

### Dark Mode

<table>
  <tr>
    <td align="center"><img src="screenshots/trends-dark.png" width="400" alt="Trends"><br><strong>Trends & Analytics</strong></td>
    <td align="center"><img src="screenshots/insights-dark.png" width="400" alt="Insights"><br><strong>Smart Insights</strong></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/scheduled-dark.png" width="400" alt="Scheduled"><br><strong>Scheduled Transactions</strong></td>
    <td align="center"><img src="screenshots/rules-dark.png" width="400" alt="Rules"><br><strong>Rules & Automation</strong></td>
  </tr>
</table>

## Installation

### Download DMG (Recommended)

1. Download the latest `.dmg` from [Releases](https://github.com/Kolomaster68/mint-leaf/releases/latest)
2. Open the DMG and drag Mint Leaf to your Applications folder
3. On first launch, right-click the app and select **Open** (macOS Gatekeeper requires this for unsigned apps)

### Build from Source

1. Clone the repository
2. Open `MintLeaf.xcodeproj` in Xcode 16+
3. Select the `MintLeaf_macOS` or `MintLeaf_iOS` scheme
4. Build and run

No external dependencies required.

## Onboarding

New users are guided through a polished onboarding flow with three options:

1. **Start Fresh** — Jump straight into the app
2. **Load Sample Data & Take a Tour** — Explore with demo data and a guided walkthrough
3. **Load Sample Data** — Demo data without the tour

<table>
  <tr>
    <td align="center"><img src="screenshots/onboarding-welcome.png" width="400" alt="Welcome"><br><strong>Welcome</strong></td>
    <td align="center"><img src="screenshots/onboarding-features.png" width="400" alt="Features"><br><strong>Features Overview</strong></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/onboarding-setup-dark.png" width="400" alt="Setup Dark"><br><strong>Setup (Dark)</strong></td>
    <td align="center"><img src="screenshots/onboarding-setup-light.png" width="400" alt="Setup Light"><br><strong>Setup (Light)</strong></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/tutorial-complete-dark.png" width="400" alt="Tour Complete"><br><strong>Tour Complete</strong></td>
    <td align="center"><img src="screenshots/tutorial-imports-dark.png" width="400" alt="Tour Step"><br><strong>Guided Tour</strong></td>
  </tr>
</table>

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+1` | Overview |
| `Cmd+2` | Inbox |
| `Cmd+3` | Trends |
| `Cmd+4` | Budgets |
| `Cmd+5` | Scheduled |
| `Cmd+F` | Search |
| `Cmd+B` | Notifications |
| `Shift+Cmd+N` | New Account |

## App Icon

Mint Leaf ships with both light and dark app icons that match the system appearance. Users can also switch between them manually or upload a custom icon from Settings.

<p align="center">
  <img src="screenshots/icon-light.png" width="128" height="128" alt="Light Icon">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="screenshots/icon-dark.png" width="128" height="128" alt="Dark Icon">
</p>

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI 5 |
| Data | SwiftData |
| Platform | macOS 14+ / iOS 17+ |
| Language | Swift 6 |
| Architecture | MVVM with @Observable |

## Roadmap

Mint Leaf is under active development. Here's what's been shipped and what's coming next.

### Shipped

| Version | Feature |
|---------|---------|
| v1.0 | Accounts, Transactions, Categories, Budgets |
| v1.0 | CSV & PDF Import |
| v1.0 | Rules & Merchant Aliases |
| v1.0 | Trends & Insights |
| v1.0 | Scheduled Transactions & Subscription Calendar |
| v1.0 | Interactive Onboarding Tutorial |
| v2.0 | Multi-Currency Support (39 currencies) |
| v2.0 | Search with Filters |
| v2.0 | In-App Notification Centre |
| v2.0 | Keyboard Shortcuts |
| v2.0 | Reorganised Sidebar |
| v2.0 | DMG Distribution |
| v2.1 | XLSX (Excel) Import |
| v2.1 | Privacy Dashboard |
| v3.0 | Net Worth Tracker |
| v3.0 | Reports with CSV Export |
| v3.0 | Goals & Wishlist |
| v3.0 | Cashflow Forecast |
| v3.0 | Tags & Tag Picker |
| v3.0 | Transfer Calculation Fix |

### Coming in v3.x

These features are actively being explored for upcoming releases:

| Feature | Description |
|---------|-------------|
| **Dashboard Customisation** | Choose which cards appear on your dashboard and reorder them to suit your workflow |
| **Dark/Light Theme Refinements** | Enhanced colour palettes, improved contrast, and more consistent styling across all views |
| **Recurring Transaction Detection** | Automatically detect recurring patterns when importing bank statements and suggest scheduled transactions |
| **Expanded Keyboard Shortcuts** | More shortcuts for common actions across all views |
| **Shared Budgets** | Export and import budgets as JSON files to share with family or partners — no cloud account needed |
| **Split Transactions** | Split a single transaction across multiple categories, people, or accounts for shared expenses |

### Future Considerations

| Feature | Notes |
|---------|-------|
| Receipt Scanning | Attach photos or scan receipts to extract amounts |
| Onboarding v3 | Updated tutorial covering Net Worth, Reports, Goals, Forecast, and Tags |
| Fresh Screenshots | New screenshots showcasing all v3 features |
| Widgets | At-a-glance spending and balance widgets (requires Apple Developer account) |
| Apple Watch | Quick balance checks from your wrist (requires Apple Developer account) |
| Bank Integration | Connect accounts via Plaid or Open Banking |

Have a feature request? [Open an issue](https://github.com/Kolomaster68/mint-leaf/issues).

## Contributing

Contributions are welcome! Fork the repo, create a branch, and submit a pull request. Please keep PRs focused and include a clear description of the change.

## License

MIT License. See [LICENSE](LICENSE) for details.
