# encoding: UTF-8
require 'csv'

class ChangeSku
  # To change this template use File | Settings | File Templates.
  def initialize
    @directory = "#{Rails.root}/vendor/products"
    @file = 'datos.csv'
    @logger = Logger.new(File.join(@directory, 'logfile.log'))
  end

  def run
    interchange_row
  end

  def interchange_row
    CSV.foreach(File.join(@directory, @file), encoding: "ISO-8859-1", headers: true,  col_sep: ';') do |row|
      begin
        v = Spree::Variant.find_by_sku(row[1])
        v.update_attributes(:sku => row[0])
        puts "Actualizado articulo #{row[0]}".white.on_blue unless Rails.env.production?
      rescue Exception => e
        @logger.error("#{e.class.name}: #{e.message}")
        @logger.error(e.backtrace * "\n")
        @logger.info '=' * 50
        next
      end
    end
  end
end