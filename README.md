# KstApp

ON4KST Chat app with Push Notification support. Based on the great work done
by the [QLog
team](https://github.com/foldynl/QLog/blob/master/service/kstchat/KSTChat.cpp).

## Installation
Unfortunately KstApp currently is not available from the Apple Appstore. However 
you can either compile it from source using XCode or install it using [AltStore](https://altstore.io/). Here is the [altstore source](https://raw.githubusercontent.com/chrbayer84/KstApp/refs/heads/main/altstore-source.json) file. Tap "Sources" on the bottom and then the plus in the top left corner. Then tap the KstApp source and click on the "free" button next to KstApp.

## Screenshots
### iPhone Portrait
<img src="https://github.com/chrbayer84/KstApp/blob/main/iphone.png?raw=true" height="600"/>
### iPhone landscape
<img src="https://github.com/chrbayer84/KstApp/blob/main/iphone_landscape.png?raw=true" width="600"/>
### iPad
<img src="https://github.com/chrbayer84/KstApp/blob/main/ipad.png?raw=true" width="600"/>



## Features

### Core Features
- iOS 17.0+ support
- Universal app (iPhone and iPad)

### ON4KST Chat Integration
- **Multiple Chat Rooms**: Support for all ON4KST chat rooms (50/70 MHz, 144/432 MHz, Microwave, etc.)
- **User Management**: View online users with callsign, grid square, and azimuth
- **Message Highlighting**: Customizable rules to highlight important messages
- **Grid Square Support**: Full Maidenhead grid square calculations and azimuth display
- **Secure Authentication**: Username/password storage with secure keychain integration

## Getting Started

1. Open `KstApp.xcodeproj` in Xcode
2. Select your target device or simulator
3. Build and run the project (⌘+R)
4. Navigate to the "ON4KST Chat" tab
5. Tap "Connect" to enter your ON4KST credentials
6. Select a chat room and start chatting!

### Managing Highlight Rules
1. Navigate to the "Rules" tab
2. Tap "Add" to create new highlight rules
3. Configure conditions based on sender, message content, or grid square
4. Set room-specific or global rules
5. Enable/disable rules as needed

### Chat Features
- **Send Messages**: Type in the message input field and tap "Send"
- **View Users**: See all online users in the right panel
- **Highlighted Messages**: Important messages are highlighted based on your rules

## Requirements

- Xcode 15.0 or later
- iOS 17.0 or later
- Swift 5.0
- Network connectivity for ON4KST chat server access

## License

GPL v3
