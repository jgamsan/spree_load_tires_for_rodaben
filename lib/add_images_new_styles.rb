class AddImagesNewStyles
  def initialize
    @wd = "#{Rails.root}/public/spree/products"
    @images = []
  end

  def run
    get_total_images
    add_images
    print_report
  end

  def get_total_images
    @images = Spree::Image.all
  end

  def add_images
    @images.each do |item|

    end
  end

end