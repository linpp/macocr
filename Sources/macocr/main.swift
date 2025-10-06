import Cocoa
import Vision
import CoreImage


// https://developer.apple.com/documentation/vision/vnrecognizetextrequest

let MODE = VNRequestTextRecognitionLevel.accurate // or .fast
let USE_LANG_CORRECTION = true
var REVISION:Int
if #available(macOS 11, *) {
    REVISION = VNRecognizeTextRequestRevision2
} else {
    REVISION = VNRecognizeTextRequestRevision1
}

@discardableResult func writeCGImage(_ image: CGImage, to destinationURL: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, kUTTypePNG, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

func convertCIImageToCGImage(inputImage: CIImage) -> CGImage! {
    let context = CIContext(options: nil)
    return context.createCGImage(inputImage, from: inputImage.extent)
}

func convertCGImageToCIImage(inputImage: CGImage) -> CIImage! {
    return CIImage(cgImage: inputImage)
}

func main(args: [String]) -> Int32 {
    guard CommandLine.arguments.count > 1 else {
        fputs(String(format: "usage: %1$@ image [-min:<minimum-text-height>] [-cropx:x] [-cropy:y] [-footer:f] [-insets:<edge-inset-list>]\n", CommandLine.arguments[0]), stderr)
        return 1
    }
  
    var cropx : CGFloat = 0.0
    var cropy : CGFloat = 0.0
    var footer : CGFloat = 0.0
    var src = ""
    var min : Float = 0.0
    var words : [String] = ["correct"]
    var crop : [NSEdgeInsets] = []
    var debug = false
    var sep = "\n"
    let navbar: CGFloat = 48
 
  // Flag ideas:
    // --version
    // Print REVISION
    // --langs
    // guard let langs = VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate, revision: REVISION)
    // --fast (default accurate)
    // --fix (default no language correction)
  
    for arg in args {
      if arg == "-d" {
        debug = true
      } else if arg.hasPrefix("-insets") {
        let i = arg.firstIndex(of:":") ?? arg.endIndex
        let regions = String(arg.suffix(from: arg.index(i, offsetBy:1))).components(separatedBy: ":").map { String($0) }
        for region in regions {
          let r = region.components(separatedBy: ",").map { CGFloat(Float($0)!) }
          let rect = NSEdgeInsets(top:r[0], left:r[1], bottom:r[2]+navbar, right:r[3])
          crop.append(rect)
        }
        sep = " "
      } else if arg.hasPrefix("-cropy") {
        let i = arg.firstIndex(of:":") ?? arg.endIndex
        cropy = CGFloat(Float(arg.suffix(from: arg.index(i, offsetBy:1)))!)
      } else if arg.hasPrefix("-footer") {
        let i = arg.firstIndex(of:":") ?? arg.endIndex
        footer = CGFloat(Float(arg.suffix(from: arg.index(i, offsetBy:1)))!)
      } else if arg.hasPrefix("-cropx") {
          let i = arg.firstIndex(of:":") ?? arg.endIndex
          cropx = CGFloat(Float(arg.suffix(from: arg.index(i, offsetBy:1)))!)
      } else if arg.hasPrefix("-min") {
        let i = arg.firstIndex(of:":") ?? arg.endIndex
        min = Float(arg.suffix(from: arg.index(i, offsetBy:1)))!
      } else if arg.hasPrefix("-words") {
        let i = arg.firstIndex(of:":") ?? arg.endIndex
        let fileName = String(arg.suffix(from: arg.index(i, offsetBy:1)))
        guard let contents = try? String(contentsOfFile: fileName) else {
          continue
        }
        let myStrings = contents.components(separatedBy: .newlines).map { String($0) }
        var newStrings: String = ""
        for s in myStrings {
          if let range = s.range(of:" - ") {
            newStrings += String(s[..<range.lowerBound]) + " "
          } else {
            newStrings += s + " "
          }
        }
        words = Array(Set(newStrings.split(separator:" ").map { String($0) }))
        if debug {
          print(words)
        }
      }
      else {
        src = arg
      }
    }

    guard let img = NSImage(byReferencingFile: src) else {
        fputs("Error: failed to load image '\(src)'\n", stderr)
        return 1
    }

  if cropx > 0 || cropy > 0 || footer > 0 {
    let rect = NSEdgeInsets(top:cropy, left:cropx, bottom:navbar+footer, right:0)
    crop.append(rect)
  } else if crop.count == 0 {
    crop.append(NSEdgeInsets(top:navbar+footer, left:0, bottom:navbar+footer, right:0))
  }

  guard let cgImg = img.cgImage(forProposedRect: &img.alignmentRect, context: nil, hints: nil) else {
    fputs("Error: failed to convert NSImage to CGImage for '\(src)'\n", stderr)
    return 1
  }

  let ciImg = convertCGImageToCIImage(inputImage:cgImg)
  let currentFilter = CIFilter(name: "CIGammaAdjust")!
  currentFilter.setValue(ciImg, forKey: kCIInputImageKey)
  currentFilter.setValue(0.5, forKey: "inputPower")
  let imgRef = convertCIImageToCGImage(inputImage:currentFilter.outputImage!)!

//  writeCGImage(_:imgRef, to:URL(string:"file:///Volumes/RamDisk/ocrnew.png")!)

  let request = VNRecognizeTextRequest { (request, error) in
    let observations = request.results as? [VNRecognizedTextObservation] ?? []
    let obs : [String] = observations.map { $0.topCandidates(1).first?.string ?? ""}
    print(obs.joined(separator: sep))
  }
  request.recognitionLevel = MODE
  request.usesLanguageCorrection = USE_LANG_CORRECTION
  request.revision = REVISION
  if min > 0.0 {
    request.minimumTextHeight = min
  }
  request.customWords = words
  
  if crop.count > 1 {
    sep = " "
  }
  
  for crect in crop {
    let rect = CGRect(x:img.alignmentRect.minX+crect.left, y:img.alignmentRect.minY+crect.top, width:img.alignmentRect.width-(crect.left+crect.right), height:img.alignmentRect.height-(crect.top+crect.bottom))
    if debug {
      print("=", terminator:"")
      print(rect)
    }
    let cropRef = imgRef.cropping(to: rect)!
    try? VNImageRequestHandler(cgImage: cropRef, options: [:]).perform([request])
  }
  
    return 0
}
exit(main(args: CommandLine.arguments))
