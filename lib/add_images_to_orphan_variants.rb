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
    @diferencia.each do |v|
      if Spree::Product.exists?(v.product_id)
        unless v.product.is_moto?
          variant = Spree::Variant.find(v)
          img = Spree::Image.new(:attachment => File.open(@default))
          img.save!
          variant.images << img
          j += 1
        end
        print "Ejecutando variante #{j} de un total de #{i}".white.on_blue
      else
        v.destroy
      end
    end
  end


end