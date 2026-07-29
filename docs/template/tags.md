# ImgFlow Tag System - Standardized Interface

All ImgFlow providers must implement these standardized tags to ensure compatibility across different image processing backends.

## 🏷️ Standard Tag Interface

### Core Tags
- `resize` - Change image dimensions
- `crop` - Crop to specific aspect ratio
- `quality` - Set compression quality
- `format` - Convert to different formats
- `optimize` - General optimization
- `watermark` - Add watermarks

### Advanced Tags
- `rotate` - Rotate image
- `flip` - Flip horizontally/vertically
- `blur` - Apply blur effects
- `sharpen` - Sharpen image
- `grayscale` - Convert to grayscale

## 🔄 Provider Implementation

Each provider implements the same interface but translates to their specific API calls.

```ruby
module ImgFlow
  module Tags
    class BaseTag
      def initialize(provider)
        @provider = provider
      end
      
      def process(input_path, options = {})
        raise NotImplementedError, "Provider must implement #{self.class.name}"
      end
    end
  end
end
```
