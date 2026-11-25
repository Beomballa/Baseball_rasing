import UIKit
import SpriteKit

/// 홈 구장 자산만 고른다. 경기 ID·판정·저장된 팀 정보는 변경하지 않는다.
@MainActor enum InplayWideStadiumArt {
    struct PixelSize: Decodable {
        let width: Double
        let height: Double
        var size: CGSize { CGSize(width: width, height: height) }
    }
    struct BoardRect: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        var valid: Bool {
            [x,y,width,height].allSatisfy(\.isFinite) && x >= 0 && y >= 0
                && width > 0 && height > 0 && x+width <= 1 && y+height <= 1
        }
        /// 완성 원화의 좌상단 좌표다. SpriteKit 반전은 기존 장면에서 한 번만 한다.
        func topLeftFrame(in canvas: CGSize) -> CGRect {
            CGRect(x:x*canvas.width,y:y*canvas.height,width:width*canvas.width,height:height*canvas.height)
        }
    }
    struct Venue: Decodable {
        let name: String
        let asset: String
        let pixelSize: PixelSize
        let sha256: String
        let boardRect: BoardRect
        var valid: Bool {
            pixelSize.size == CGSize(width:1536,height:1024) && boardRect.valid
                && asset.hasPrefix("venues/") && !asset.contains("..")
        }
    }
    struct Catalog: Decodable {
        let version: Int
        let coordinateOrigin: String
        let rectUnits: String
        let venues: [String:Venue]
        let aliases: [String:String]
        func canonicalID(_ homeID: String) -> String? {
            let id=aliases[homeID] ?? homeID
            return venues[id] == nil ? nil:id
        }
    }
    final class Artwork {
        let canonicalID: String
        let venue: Venue
        let image: UIImage
        init(id:String,venue:Venue,image:UIImage) {
            canonicalID=id;self.venue=venue;self.image=image
        }
        lazy var texture: SKTexture = {
            let value=SKTexture(image:image);value.filteringMode = .nearest;return value
        }()
    }
    static let directory="MatchArt/WideStadiums"
    static let catalog: Catalog? = {
        guard let url=Bundle.main.url(forResource:"venues",withExtension:"json",subdirectory:directory),
              let data=try? Data(contentsOf:url),let value=try? JSONDecoder().decode(Catalog.self,from:data),
              value.version == 241,value.coordinateOrigin == "topLeft",value.rectUnits == "normalized",
              value.venues.values.allSatisfy(\.valid),value.aliases.values.allSatisfy({value.venues[$0] != nil}) else {return nil}
        return value
    }()
    private static let cache: NSCache<NSString,Artwork> = {
        let value=NSCache<NSString,Artwork>()
        value.countLimit=2;value.totalCostLimit=16*1024*1024
        return value
    }()
    static func venue(for stadium: StadiumIdentity) -> Venue? {
        guard let catalog,let id=catalog.canonicalID(stadium.key) else {return nil}
        return catalog.venues[id]
    }
    static func artwork(for stadium: StadiumIdentity) -> Artwork? {
        guard let catalog,let id=catalog.canonicalID(stadium.key),let venue=catalog.venues[id] else {return nil}
        if let value=cache.object(forKey:id as NSString) {return value}
        let path=URL(fileURLWithPath:venue.asset)
        guard let url=Bundle.main.url(forResource:path.deletingPathExtension().lastPathComponent,
                withExtension:path.pathExtension,subdirectory:directory+"/venues"),
              let image=UIImage(contentsOfFile:url.path),image.size == venue.pixelSize.size else {return nil}
        let value=Artwork(id:id,venue:venue,image:image)
        // 필요한 구장만 불러온다. 캐시 2개·16MiB는 NSCache의 권고 상한이다.
        cache.setObject(value,forKey:id as NSString,cost:Int(image.size.width*image.size.height)*4)
        return value
    }
}
