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
import SDWebImage
import Firebase
import FirebaseUI

class RestaurantDetailViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, NewReviewViewControllerDelegate {

  var titleImageURL: URL?
  var restaurant: Restaurant?
  var restaurantReference: DocumentReference?

  var localCollection: LocalCollection<Review>!

  static func fromStoryboard(_ storyboard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)) -> RestaurantDetailViewController {
    // ストーリーボードから指定IDのビューコントローラを返す
    let controller = storyboard.instantiateViewController(withIdentifier: "RestaurantDetailViewController") as! RestaurantDetailViewController
    return controller
  }

  @IBOutlet var tableView: UITableView!
  // TOP画像エリアのビュー
  @IBOutlet var titleView: RestaurantTitleView!

  let backgroundView = UIImageView()

  override func viewDidLoad() {
    super.viewDidLoad()
    debug("restaurantReference:\(restaurantReference)")

    self.title = restaurant?.name
    navigationController?.navigationBar.tintColor = UIColor.white

    // 背景にピザモンスター画像をセットする
    backgroundView.image = UIImage(named: "pizza-monster")!
    backgroundView.contentScaleFactor = 2
    backgroundView.contentMode = .bottom
    // テーブルビューの背景にピザモンスター画像をセットする
    tableView.backgroundView = backgroundView
    tableView.tableFooterView = UIView()

    tableView.dataSource = self
    tableView.rowHeight = UITableViewAutomaticDimension
    tableView.estimatedRowHeight = 140

    // retingsサブコレクションのクエリーオブジェクト生成する
    let query = restaurantReference!.collection("ratings")
    
    // LocalCollectionオブジェクトを生成する。ratingsコレクションの参照とアップデートハンドラーを渡す
    localCollection = LocalCollection(query: query) { [unowned self] (changes) in
      // changes: DocumentChanges
      debug()
      
      // テーブルビューの背景画像を調整する
      if self.localCollection.count == 0 {
        self.tableView.backgroundView = self.backgroundView
        return
      } else {
        self.tableView.backgroundView = nil
      }
      var indexPaths: [IndexPath] = []

      // Only care about additions in this block, updating existing reviews probably not important
      // as there's no way to edit reviews.
      // .addなdocumentChangeだけでfor文する
      for addition in changes.filter({ $0.type == .added }) {
        // 指定されたドキュメントのインデックス番号を調べる
        let index = self.localCollection.index(of: addition.document)!
        // インデックスパスを生成する
        let indexPath = IndexPath(row: index, section: 0)
        indexPaths.append(indexPath)
      }
      // 追加ドキュメントをテーブルビューへ表示させる
      self.tableView.insertRows(at: indexPaths, with: .automatic)
    }
  }

  deinit {
    debug()
    // リスナーを解放する
    localCollection.stopListening()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    debug()
    // ratingsコレクションのリスナーをセットする
    localCollection.listen()
    // TOPエリアにテキストをセットする
    titleView.populate(restaurant: restaurant!)
    if let url = titleImageURL {
      // TOPエリアに背景画像をセットする
      titleView.populateImage(url: url)
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    debug()
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    set {}
    get {
      return .lightContent
    }
  }

  // ナビバー右ボタン
  @IBAction func didTapAddButton(_ sender: Any) {
    debug("レビュー投稿画面を表示する")
    // レビュー投稿画面を表示する
    let controller = NewReviewViewController.fromStoryboard()
    controller.delegate = self
    self.navigationController?.pushViewController(controller, animated: true)
  }

  // MARK: - UITableViewDataSource

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    // Reviewオブジェクトの数を返す
    return localCollection.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

    let cell = tableView.dequeueReusableCell(withIdentifier: "ReviewTableViewCell",
                                             for: indexPath) as! ReviewTableViewCell
    let review = localCollection[indexPath.row]
    // セルにデータをセットする
    cell.populate(review: review)
    return cell
  }

  // MARK: - NewReviewViewControllerDelegate

  // 新規レビュー画面のDoneボタンがタップされた
  func reviewController(_ controller: NewReviewViewController, didSubmitFormWithReview review: Review) {
    //
    // Review: ユーザーが入力したReview構造体
    
    // このレストランへの参照を取得する
    guard let reference = restaurantReference else { return }
    // このレストランのレビューコレクションを取得する
    let reviewsCollection = reference.collection("ratings")
    // 自動生成IDを持つ新しいドキュメントのDocumentReferenceを生成する
    let newReviewReference = reviewsCollection.document()

    // Writing data in a transaction

    let firestore = FB.db
    firestore.runTransaction({ (transaction, errorPointer) -> Any? in
      // transaction: これを使ってread、writeをアトミックに実行する。読み込んだデータがトランザクションの外側で変更されたら、Firestoreはこのブロックをリトライする。５回リトライに失敗したらトランザクションは失敗となる。
      //              このブロックは数回実行されるため、副作用的を起こさないように気をつける。
      //              トランザクションはオンラインで実行する必要がある。オフラインだと失敗する。
      
      // Read data from Firestore inside the transaction, so we don't accidentally
      // update using stale client data. Error if we're unable to read here.
      let restaurantSnapshot: DocumentSnapshot
      do {
        // DocumentReferenceからDocumentSnapshotを取得する
        try restaurantSnapshot = transaction.getDocument(reference)
      } catch let error as NSError {
        errorPointer?.pointee = error
        return nil
      }

      // Error if the restaurant data in Firestore has somehow changed or is malformed.
      guard let restaurant = restaurantSnapshot.data().flatMap(Restaurant.init(dictionary:)) else {
        let error = NSError(domain: "FriendlyEatsErrorDomain", code: 0, userInfo: [
          NSLocalizedDescriptionKey: "Unable to write to restaurant at Firestore path: \(reference.path)"
          ])
        errorPointer?.pointee = error
        return nil
      }

      // Update the restaurant's rating and rating count and post the new review at the
      // same time.
      let newAverage = (Float(restaurant.ratingCount) * restaurant.averageRating + Float(review.rating))
        / Float(restaurant.ratingCount + 1)
      
      // このレストランのサブコレクションratingsにユーザーの新規レビューのドキュメントを書き込む
      transaction.setData(review.dictionary, forDocument: newReviewReference)
      // このレストランのドキュメントのフィールドを更新する。
      transaction.updateData([
        "numRatings": restaurant.ratingCount + 1,
        "avgRating": newAverage
        ], forDocument: reference)
      return nil
    }) { (object, error) in
      // 完了ブロック
      if let error = error {
        // ブロックが失敗した場合
        print(error)
      } else {
        // ブロックが成功した場合
        // Pop the review controller on success
        if self.navigationController?.topViewController?.isKind(of: NewReviewViewController.self) ?? false {
          // レビュー入力画面を閉じる
          self.navigationController?.popViewController(animated: true)
        }
      }
    }

  }

}

// TOP画像エリアのビュー
class RestaurantTitleView: UIView {

  @IBOutlet var nameLabel: UILabel!

  @IBOutlet var categoryLabel: UILabel!

  @IBOutlet var cityLabel: UILabel!

  @IBOutlet var priceLabel: UILabel!

  @IBOutlet var starsView: ImmutableStarsView! {
    didSet {
      starsView.highlightedColor = UIColor.white.cgColor
    }
  }

  @IBOutlet var titleImageView: UIImageView! {
    didSet {
      let gradient = CAGradientLayer()
      gradient.colors = [UIColor(red: 0, green: 0, blue: 0, alpha: 0.6).cgColor, UIColor.clear.cgColor]
      gradient.locations = [0.0, 1.0]

      gradient.startPoint = CGPoint(x: 0, y: 1)
      gradient.endPoint = CGPoint(x: 0, y: 0)
      gradient.frame = CGRect(x: 0,
                              y: 0,
                              width: UIScreen.main.bounds.width,
                              height: titleImageView.bounds.height)

      titleImageView.layer.insertSublayer(gradient, at: 0)
      titleImageView.contentMode = .scaleAspectFill
      titleImageView.clipsToBounds = true
    }
  }

  // TOPエリアに背景画像をセットする
  func populateImage(url: URL) {
    titleImageView.sd_setImage(with: url)
  }

  // TOPエリアにテキストをセットする
  func populate(restaurant: Restaurant) {
    nameLabel.text = restaurant.name
    starsView.rating = Int(restaurant.averageRating.rounded())
    categoryLabel.text = restaurant.category
    cityLabel.text = restaurant.city
    priceLabel.text = priceString(from: restaurant.price)
  }

}

class ReviewTableViewCell: UITableViewCell {

  @IBOutlet var usernameLabel: UILabel!

  @IBOutlet var reviewContentsLabel: UILabel!

  @IBOutlet var starsView: ImmutableStarsView!

  func populate(review: Review) {
    usernameLabel.text = review.username
    reviewContentsLabel.text = review.text
    starsView.rating = review.rating
  }

}
