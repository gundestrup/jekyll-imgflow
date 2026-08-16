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

## Referencing Images

Image references in `{% imgflow %}` tags use **exact filenames** relative to the
`originals` directory:

```liquid
{% imgflow photo.jpg resize width:800 %}
{% imgflow subfolder/banner.png format:webp %}
{% imgflow /assets/images/originals/header.jpg optimize %}
```

### Limitations

- **No fuzzy matching** — `photo.jpg` will not resolve to `photo.jpeg`.
  The filename must match exactly.
- **No build-time autocomplete** — the Jekyll plugin itself does not suggest
  image names while running `jekyll build` or `jekyll serve`.
- **Editor autocomplete available** — install the
  [Jekyll ImgFlow VS Code extension](https://github.com/gundestrup/jekyll-imgflow-vscode)
  for image-name suggestions while writing `{% imgflow %}` tags in Markdown.
- **Error on not found** — if the image doesn't exist, the build logs an error
  and the tag outputs an HTML comment (`<!-- ImgFlow Error: ... -->`).

Future versions may add "did you mean" suggestions when an image name is
close to an existing file.
