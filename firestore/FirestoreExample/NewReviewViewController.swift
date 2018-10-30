//
//  Copyright (c) 2016 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import UIKit
import Firebase

class NewReviewViewController: UIViewController, UITextFieldDelegate {

  static func fromStoryboard(_ storyboard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)) -> NewReviewViewController {
    // ストーリーボードから指定IDのビューコントローラを返す
    let controller = storyboard.instantiateViewController(withIdentifier: "NewReviewViewController") as! NewReviewViewController
    return controller
  }

  weak var delegate: NewReviewViewControllerDelegate?

  @IBOutlet var doneButton: UIBarButtonItem!

  @IBOutlet var ratingView: RatingView! {
    // レーティングビューが初期化された
    didSet {
      // レーティングビューにイベントハンドラーを追加する
      debug("レーティングビューへイベントハンドラーを追加")
      ratingView.addTarget(self, action: #selector(ratingDidChange(_:)), for: .valueChanged)
    }
  }

  @IBOutlet var reviewTextField: UITextField! {
    // テキストフィールドが初期化された
    didSet {
      // テキストフィールドにイベントハンドラーを追加する
      debug("テキストフィールドへイベントハンドラーを追加")
      reviewTextField.addTarget(self, action: #selector(textFieldTextDidChange(_:)), for: .editingChanged)
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Doneボタンを無効化する
    doneButton.isEnabled = false
    reviewTextField.delegate = self
  }

  // キャンセルボタンハンドラー
  @IBAction func cancelButtonPressed(_ sender: Any) {
    debug("キャンセルボタンがタップされた")
    self.navigationController?.popViewController(animated: true)
  }

  // Doneボタンハンドラー
  @IBAction func doneButtonPressed(_ sender: Any) {
    // 新規レビューオブジェクトを生成する
    let review = Review(rating: ratingView.rating!,
                        userID: Auth.auth().currentUser!.uid,
                        username: Auth.auth().currentUser?.displayName ?? "Anonymous",
                        text: reviewTextField.text!,
                        date: Date())  // 現在の日付
    // 入力が完了したことをデリゲートに伝える
    delegate?.reviewController(self, didSubmitFormWithReview: review)
  }

  // レートハンドラー
  @objc func ratingDidChange(_ sender: Any) {
    debug("レートが変更しました sender:\(sender)")
    updateSubmitButton()
  }

  // テキストフィールドが空かどうかの判定
  func textFieldIsEmpty() -> Bool {
    guard let text = reviewTextField.text else { return true }
    // 文字列の前後の空白を削除して、空かどうか判定する
    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func updateSubmitButton() {
    // レートとレビューの両方があればDoneボタンを有効化する
    doneButton.isEnabled = (ratingView.rating != nil && !textFieldIsEmpty())
  }

  // テキストフィールドハンドラー
  @objc func textFieldTextDidChange(_ sender: Any) {
    debug("レビューが変更されました sender:\(sender)")
    updateSubmitButton()
  }

}

protocol NewReviewViewControllerDelegate: NSObjectProtocol {
  func reviewController(_ controller: NewReviewViewController, didSubmitFormWithReview review: Review)
}


