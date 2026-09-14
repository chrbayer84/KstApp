import UIKit
import SwiftUI

class ViewController: UIViewController {

    private var tabBarControllerInstance: UITabBarController?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleDeepLinkNotification(_:)), name: NSNotification.Name("HandleDeepLink"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleDeepLinkNotification(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? URL else { return }
        
        // Example: kstapp://chat
        if url.host == "chat" {
            tabBarControllerInstance?.selectedIndex = 0
        }
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Create a tab bar controller for navigation
        let tabBarController = UITabBarController()
        self.tabBarControllerInstance = tabBarController
        
        // KST Chat view
        let chatVC = createKSTChatViewController()
        chatVC.tabBarItem = UITabBarItem(title: "ON4KST Chat", image: UIImage(systemName: "message"), tag: 0)
        
        // Highlight Rules view
        let rulesVC = createHighlightRulesViewController()
        rulesVC.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gearshape"), tag: 1)
        
        tabBarController.viewControllers = [chatVC, rulesVC]
        
        // Add tab bar controller as child
        addChild(tabBarController)
        view.addSubview(tabBarController.view)
        tabBarController.didMove(toParent: self)
        
        // Set up constraints
        tabBarController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabBarController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabBarController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func createKSTChatViewController() -> UIViewController {
        let hostingController = UIHostingController(rootView: KSTChatView())
        return hostingController
    }
    
    private func createHighlightRulesViewController() -> UIViewController {
        let hostingController = UIHostingController(rootView: ChatHighlightRulesView())
        return hostingController
    }
}
