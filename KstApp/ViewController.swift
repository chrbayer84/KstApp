import UIKit
import SwiftUI

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Create a tab bar controller for navigation
        let tabBarController = UITabBarController()
        
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
