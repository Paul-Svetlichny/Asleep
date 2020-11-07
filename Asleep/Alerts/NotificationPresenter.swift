//
//  NotificationPresenter.swift
//  GoogleMapsTestCase
//
//  Created by Paul Svetlichny on 05.11.2020.
//

import UIKit

struct NotificationPresenter {
    private static let defaultCancelAlert = UIAlertAction.init(title: "Okay", style: .cancel)

    static func show(_ alert: UIAlertController.Style, in viewController: UIViewController, title: String?, message: String?, actions: [UIAlertAction]?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: alert)

        if let actions = actions {
            actions.forEach { action in
                alert.addAction(action)
            }
        } else {
            alert.addAction(defaultCancelAlert)
        }
        
        viewController.present(alert, animated: true, completion: nil)
    }
}


