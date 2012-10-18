# encoding: UTF-8
require 'csv'

class ImportTiresOfMoto

  def initialize()
    @directory = "#{Rails.root}/vendor/products"
    @file = "datos.csv"
    @image_wd = "#{Rails.root}/vendor/products/images/pic"
    @total = []
    I18n.locale = 'es'
  end

  def run
    load_from_csv
    send_mail
  end

  def load_from_csv
    hoy = Date.today
    CSV.foreach(File.join(@directory, @file)) do |row|
      begin
        if Spree::Variant.existe_moto_tire(row[1]) #buscar por SKU

        else
          i += 1
          # crear uno nuevo
          product = Spree::Product.new
          product.name = row[6]
          product.permalink = row[6].downcase.gsub(/\s+/, '-').gsub(/[^a-zA-Z0-9_]+/, '-')
          product.sku = hoy.strftime("%y%m%d%H%m") + i.to_s
          product.available_on = hoy - 1.day
          product.price = price
          product.cost_price = cost_price
        end
      rescue Exception => e

      end
    end
  end

  def send_mail

  end


end
