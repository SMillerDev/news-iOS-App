//
//  OCTextView.swift
//  iOCNews
//
//  Created by Sean Molenaar on 19/12/2017.
//  Copyright © 2017 Peter Hedlund. All rights reserved.
//

import UIKit

class OCTextView: UITextView {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        addObserver(self, forKeyPath: "contentSize", options: .new, context: nil)
    }
    
    deinit {
        removeObserver(self, forKeyPath: "contentSize")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if intrinsicContentSize.equalTo(self.bounds.size) {
            invalidateIntrinsicContentSize()
        }
    }
    
    @objc(textContainerInset)
    override var textContainerInset: UIEdgeInsets { get {return .zero} set {} }
    
    override var intrinsicContentSize: CGSize {
        var intrinsicContentSize: CGSize = self.sizeThatFits(bounds.size)
        intrinsicContentSize.width += self.textContainerInset.left + self.textContainerInset.right + 14
        intrinsicContentSize.height += self.textContainerInset.top + self.textContainerInset.bottom + 14
        return intrinsicContentSize
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        let textView: UITextView = object as! UITextView
        let topOffset = (textView.bounds.size.height - textView.contentSize.height * textView.zoomScale) / 2
        textView.contentOffset = CGPoint(x: 0, y: -topOffset)
    }

}
