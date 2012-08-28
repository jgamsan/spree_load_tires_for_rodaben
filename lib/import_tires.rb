require 'yaml'

class ImportTires

  def initialize()
    @final = "#{Rails.root}/vendor/products/listado-neumaticos.yml"
  end

  def export_to_csv
    fileName = File.open('.yml', 'w')
    CSV.open(@final, "wb") do |row|
      @total.each do |element|
        #[nombre, stock, precio, descuento, precio final]
        row << element
      end
    end
  end

end
