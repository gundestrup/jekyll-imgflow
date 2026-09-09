# frozen_string_literal: true

module JekyllImgFlow
  # Inline CSS and JS for the image modal/lightbox feature.
  # Injected by hooks.rb into pages that contain data-imgflow-modal triggers.
  module ModalAssets
    CSS = <<~CSS
      .imgflow-modal-overlay{position:fixed;inset:0;background:rgba(0,0,0,.85);
      display:flex;align-items:center;justify-content:center;z-index:9999;
      cursor:pointer;animation:imgflow-fade .15s ease-out}
      .imgflow-modal-image{max-width:90vw;max-height:90vh;object-fit:contain;
      cursor:auto;border-radius:4px;box-shadow:0 4px 30px rgba(0,0,0,.5)}
      .imgflow-modal-close{position:absolute;top:1rem;right:1rem;
      background:rgba(255,255,255,.2);border:none;color:#fff;font-size:2rem;
      width:3rem;height:3rem;border-radius:50%;cursor:pointer;
      display:flex;align-items:center;justify-content:center;line-height:1}
      .imgflow-modal-close:hover{background:rgba(255,255,255,.4)}
      @keyframes imgflow-fade{from{opacity:0}to{opacity:1}}
    CSS

    JS = <<~JS
      (function(){
      function openModal(src,alt){
      var o=document.createElement('div');
      o.className='imgflow-modal-overlay';
      var i=document.createElement('img');
      i.src=src;i.alt=alt||'';i.className='imgflow-modal-image';
      var b=document.createElement('button');
      b.className='imgflow-modal-close';b.setAttribute('aria-label','Close');
      b.innerHTML='&times;';
      o.appendChild(b);o.appendChild(i);document.body.appendChild(o);
      function c(){document.body.removeChild(o);
      document.removeEventListener('keydown',k);}
      function k(e){if(e.key==='Escape')c();}
      o.addEventListener('click',function(e){
      if(e.target===o||e.target===b)c();});
      document.addEventListener('keydown',k);}
      document.addEventListener('click',function(e){
      var t=e.target.closest('[data-imgflow-modal]');
      if(!t)return;e.preventDefault();
      openModal(t.getAttribute('href'),t.getAttribute('data-imgflow-alt'));});
      })();
    JS

    def self.inject(html)
      return html unless html&.include?("data-imgflow-modal")

      style_tag = "<style>\n#{CSS}</style>"
      script_tag = "<script>\n#{JS}</script>"

      if html.include?("</head>")
        html = html.sub("</head>", "#{style_tag}\n</head>")
        html = html.sub("</body>", "#{script_tag}\n</body>") if html.include?("</body>")
      elsif html.include?("</body>")
        html = html.sub("</body>", "#{style_tag}\n#{script_tag}\n</body>")
      else
        html = "#{html}\n#{style_tag}\n#{script_tag}"
      end

      html
    end
  end

  # Modal wrapping logic for HtmlGenerator — extracted to keep HtmlGenerator
  # under the RuboCop class length limit.
  module ModalWrapper
    # Formats that produce raw URLs/srcsets (not wrappable HTML elements)
    NON_HTML_FORMATS = %w[direct_url naked_srcset].freeze

    # Check if the current markup format produces an HTML element
    def html_element?
      !NON_HTML_FORMATS.include?(@markup_format)
    end

    # Determine if modal behavior is enabled for this image
    # Per-image modal:true/false overrides config default
    # Modal is skipped when an explicit link is set
    def modal_enabled?
      return false if @attributes[:link]

      modal_attr = @attributes[:modal]
      return modal_attr.to_s == "true" if modal_attr

      @config&.image_modal ? true : false
    end

    # Pick the best image path for the modal — prefer the fallback format
    # (e.g. jpg) for maximum browser compatibility
    def modal_image_path
      fallback_ext = @config&.fallback_format ? ".#{@config.fallback_format}" : ".jpg"
      fallback = @results.find { |r| File.extname(r).downcase == fallback_ext }
      fallback || @results.last
    end

    # Wrap HTML in modal trigger anchor
    def wrap_with_modal(html)
      modal_href = html_path(modal_image_path)
      return html unless modal_href

      data_attrs = " data-imgflow-modal"
      alt = @attributes[:alt]
      data_attrs += " data-imgflow-alt=\"#{escape_attr_value(alt)}\"" if alt

      "<a href=\"#{modal_href}\"#{data_attrs}>#{html}</a>"
    end
  end
end
