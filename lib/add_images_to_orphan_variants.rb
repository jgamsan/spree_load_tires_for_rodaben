class AddImagesToOrphanVariants
  def initialize
    @default = "#{Rails.root}/app/assets/images/default.png"
    @variants = []
    @imagenes = []
    @diferencia = []
  end

  def run
    get_orphan_variants
    assign_images
  end

  def get_orphan_variants
    @variants = Spree::Variant.all.map {|x| x.id}
    @imagenes = Spree::Image.all.map {|x| x.viewable_id}
    @diferencia = @variants - @imagenes
  end

  def assign_images
    j = 1
    begin
      @diferencia.each do |v|
        variant = Spree::Variant.find(v)
        if Spree::Product.exists?(variant.product_id)
          unless variant.product.is_moto?
            img = Spree::Image.new(:attachment => File.open(@default))
            img.save!
            variant.images << img
            j += 1
          end
          print "Ejecutando variante #{j}".white.on_blue
        else
          variant.destroy
        end
      end
    rescue Exception => e
      puts "Error en variante #{variant}".white.on_red unless Rails.env.production?
    end

  end


end