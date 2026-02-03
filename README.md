

# Hamii Mobiles Inventory & POS System 📱

![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.0%2B-0175C2?logo=dart)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android-lightgrey)
![License](https://img.shields.io/badge/License-MIT-green)

Hamii Mobiles Inventory & POS System is a **specialized, offline-first** inventory management and point-of-sale solution designed specifically for mobile phone retailers. The system addresses real-world challenges such as **IMEI-based stock tracking**, **mobile trade-ins**, and **digital ledger (Khata) management**, all within a single cross-platform application.

---

## 🚀 Project Overview

This system replaces traditional manual bookkeeping used in mobile shops with a fully digital solution. Unlike generic POS software, each smartphone is treated as a **unique asset** using its IMEI number, ensuring accurate inventory control and fraud prevention.

The application supports **offline operation**, making it ideal for shops with unreliable internet connectivity. A built-in **double-entry ledger system** automatically manages customer credit and dealer payables.

---

## ✨ Key Features

### 📦 Inventory Management
- IMEI-based tracking for every mobile device  
- Categorized stock (Android, iPhone, Accessories)  
- Smart stock deletion with dealer balance adjustment  
- Low-stock alerts for accessories  

### 🛒 Point of Sale (POS)
- Dual Mode POS  
  - **Sale Mode:** Normal checkout  
  - **Refund Mode:** Secure sold-item returns  
- Trade-in (Exchange) handling in a single transaction  
- Split payments (Cash + Bank) with automatic credit booking  

### 📒 Ledger / Khata System
- Separate profiles for Dealers and Customers  
- Automatic debit/credit balancing  
- Color-coded receivable and payable indicators  
- Exportable professional A4 PDF ledger reports  

### 📊 Reports & Analytics
- Real-time profit calculation  
- Total asset value of current stock  
- Daily cash and bank balance tracking  

---

## 🛠 Technology Stack

- **Framework:** Flutter (Dart)  
- **Architecture:** MVVM  
- **State Management:** Provider  
- **Database:** Isar (NoSQL, offline-first)  
- **PDF Generation:** pdf & printing packages  
- **UI:** Material Design 3  

---

## 🖥 Supported Platforms

- Windows Desktop (Split View Layout)  
- Android Tablets (Vertical Layout)  

---

## 📸 Screenshots

> Add your screenshots in a folder named `screenshots/`

| Dashboard & POS | Inventory |
|:--:|:--:|
| pos_screen.png | inventory.png |

| Ledger | Reports |
|:--:|:--:|
| ledger.png | report.png |

---

## 📂 Project Structure

```bash
lib/
├── main.dart                 # App Entry & Theme Configuration
├── models/
│   └── schema.dart           # Isar Database Collections
├── screens/
│   ├── inventory_screen.dart
│   ├── pos_screen.dart
│   ├── ledgers_screen.dart
│   ├── reports_screen.dart
│   ├── stock_list_screen.dart
│   └── login_screen.dart
├── services/
│   ├── db_service.dart
│   ├── cart_service.dart
│   └── auth_service.dart
└── assets/                   # Images & Logos
