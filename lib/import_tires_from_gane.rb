# encoding: UTF-8
require 'csv'

class ImportTiresFromGane
  
  def initialize()
    @agent = Mechanize.new
    @final = "#{Rails.root}/vendor/products/listado-neumaticos.csv"
    @total = @no_leidos = []
    @taxons = Spree::Taxon.where(:parent_id => 2).map {|x| x.name}
    @tubes = %w(TL TT RU)
    @widths = CSV.read("#{Rails.root}/db/datas/rodaben-anchos.csv").map {|x| x[0]}
    @series = CSV.read("#{Rails.root}/db/datas/rodaben-series.csv").map {|x| x[0]}
    @llantas = CSV.read("#{Rails.root}/db/datas/rodaben-llantas.csv").map {|x| x[0]}
    @vel = CSV.read("#{Rails.root}/db/datas/rodaben-ivel.csv").map {|x| x[0]}
    @marcas = CSV.read("#{Rails.root}/db/datas/rodaben-marcas.csv").map {|x| x[0]}
  end
  
  def run
    #if login
      #read_from_gane
      #export_to_csv
      load_from_csv
    #end
  end
  
  def read_from_gane
    str = "http://galaicoasturianadeneumaticos.distritok.com/sqlcommerce/disenos/plantilla1/seccion/Catalogo.jsp?idIdioma=&idTienda=50&cPath=61"
    sch = ".//table[@class='result']//tr//td[@class='result_right']//a[@title='Siguiente ']"
    links = []
    until str.empty?
      page = @agent.get(str)
      page.search(".//table[@class='tableBox_output']//tr").each do |d|
        t = d.search("td[@width='900']//a").text
        r = d.search("td//span[@class='linCat']").map {|x| x.text}
        unless r.empty?
          if r[1] == "Consultar"
              p = k = pf = s = 0
          else
            s = r[0]
            p = r[1].to_s.delete("€").lstrip
            k = r[2].to_s.delete("%").lstrip
            pf = r[3].to_s.delete("€").lstrip
            puts "Stock es #{p}. PVP final es #{pf}"
          end
          @total << [t, s, p, k, pf]
        end
      end
      links.clear
      page.search(sch).each do |link|
        links << link[:href]
      end
      links = links.uniq
      str = links[0].to_s
      puts str
    end
  end
  
  def export_to_csv
    CSV.open(@final, "wb") do |row|
      @total.each do |element|
        #[nombre, stock, precio, descuento, precio final]
        row << element
      end
    end
  end
  
  def load_from_csv
    # [ancho, serie, llanta, vel, tube, marca, gr]
    result = []
    i = j =0
    hoy = Date.today
    productos = Spree::Product.find_by_sql("Select name from spree_products;").map {|x| x.name}.flatten
    CSV.foreach(@final) do |row|
      unless row[0].blank?
        if productos.include?(row[0]) # producto existe
          articulo = Spree::Product.find_by_name(row[0])
          articulo.update_attributes(
            :count_on_hand => set_stock(row[1]),
            :cost_price => row[4],
            :price => row[4] * 1.05 #falta de poner el precio de venta segun cliente
          )
          # actualizar los precios
        else
          result = read_format(row[0])
          i += 1
          # crear uno nuevo
          product = Spree::Product.new
          product.name = row[0]
          product.permalink = row[0].downcase.gsub(/\s+/, '-').gsub(/[^a-zA-Z0-9_]+/, '-')
          product.sku = hoy.year.to_s + hoy.month.to_s + hoy.day.to_s + "-" + i.to_s
          product.available_on = hoy - 1.day
          product.count_on_hand = set_stock(row[1])
          product.price = row[4] * 1.05 #falta de poner el precio de venta segun cliente
          product.cost_price = row[4]
          product.tire_width_id = set_width(result)
          product.tire_serial_id = set_serial(result)
          product.tire_innertube_id = set_innertube(result)
          product.tire_speed_code_id = set_speed_code(result)
          product.tire_rf = false
          product.tire_gr = result[6]
          product.tire_season = set_season(result)
          product.taxons << Spree::Taxon.find(set_catalog) #cargar categoria
          product.taxons << Spree::Taxon.find(set_brand(result)) #cargar marca
          if product.save!
            puts "Creado articulo #{row[0]}"
            j += 1
          end
        end
      end
    end
  end
  
  private
  
  def login
    login = '929'
    password = 'B36973667'
    direccion = 'http://galaicoasturianadeneumaticos.distritok.com/'
    page = @agent.get(direccion)
    gane_form = page.form('login')
    gane_form.login = login
    gane_form.password = password
    gane_form.submit
  end
  
  def read_format(rueda)
    rueda = rueda.to_s
    if rueda =~ %r{(\d+)(?:/|:)(\d+)(?:\s|:)(\D)(?:\s|:)(\d+)(?:\s|:)(\D+)(?:\s|:)(\d+[A-Z])} #1
      g = [$1,$2,$3,$4,$5,$6]
      ancho = g[0]
      serie = g[1]
      llanta = g[3]
      tube = read_tube(g[4])
      vel = g[5].scan(/[A-Z]+/)[0]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\d+)(?:/|:)(\d+)(?:\s|:)(\D)(?:\s|:)(\d+[A-Z])(?:\s|:)(\D+)(?:\s|:)(\d+)(?:/|:)(\d+[A-Z])} #2
      g = [$1,$2,$3,$4,$5,$6,$7]
      ancho = g[0]
      serie = g[1]
      llanta = g[3]
      tube = g[4]
      vel = g[6].scan(/[A-Z]+/)[0]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\S+)(?:-|:)(\S+)(?:\s|:)(\D+)(?:\s|:)(\d+[A-Z]+)} #3
      g = [$1,$2,$3,$4]
      ancho = g[0]
      serie = nil
      llanta = g[1]
      tube = g[2]
      vel = nil
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, true]
    elsif rueda =~ %r{(\S+)(?:/|:)(\d+)(?:-|:)(\S+)(?:\s|:)(\S)} #4
      g = [$1,$2,$3,$4]
      ancho = g[1]
      serie = nil
      llanta = g[2]
      tube = g[3]
      vel = nil
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, true]
    elsif rueda =~ %r{(\S+)(?:\s|:)([A-Z])(?:\s|:)(\d+)(?:\s|:)([A-Z]+)(?:\s|:)(\d+)(?:/|:)(\d+[A-Z])} #5
      g = [$1,$2,$3,$4,$5,$6]
      ancho = g[0]
      serie = g[2]
      llanta = nil
      tube = g[3]
      vel = g[5].scan(/[A-Z]+/)[0]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\d+)(?:/|:)(\d+)(?:\s|:)(\D)(?:\s|:)(\d+)(?:\s|:)(\D+)(?:\s|:)([A-Z]+)} #6
      g = [$1,$2,$3,$4,$5,$6]
      ancho = g[0]
      serie = g[1]
      llanta = g[3]
      tube = g[4]
      vel = g[5]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\d+)(?:\s|:)(\D)(?:\s|:)(\d+)(?:\s|:)(\D+)(?:\s|:)(\d+[A-Z])} #7
      g = [$1,$2,$3,$4,$5]
      ancho = g[0]
      serie = nil
      llanta = g[2]
      tube = g[3]
      vel = g[4].scan(/[A-Z]+/)[0]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\d+)(?:\s|:)(\D)(?:\s|:)(\d+[A-Z])(?:\s|:)(\D+)(?:\s|:)(\d+)(?:/|:)(\d+[A-Z])} #8
      g = [$1,$2,$3,$4,$5,$6]
      ancho = g[0]
      serie = nil
      llanta = g[2]
      tube = g[3]
      vel = g[5].scan(/[A-Z]+/)[0]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\d+)(?:/|:)(\d+)(?:\s|:)(\D)(?:\s|:)(\S+)(?:\s|:)(\D+)(?:\s|:)(\d+)(?:/|:)(\d+[A-Z])} #9
      g = [$1,$2,$3,$4,$5,$6,$7]
      ancho = g[0]
      serie = g[1]
      llanta = g[3]
      tube = g[4]
      vel = g[6].scan(/[A-Z]+/)[0]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\d+)(?:/|:)(\d+)(?:\s|:)(\D)(?:\s|:)(\S+)(?:\s|:)(\D+)(?:\s|:)(\S+)} #10
      g = [$1,$2,$3,$4,$5,$6]
      ancho = g[0]
      serie = g[1]
      llanta = g[3]
      tube = g[4]
      vel = g[5].scan(/[A-Z]+/)[0]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\d+)(?:/|:)(\d+)(?:\s|:)(\D)(?:\s|:)(\S+)(?:\s|:)(\S+)(?:/|:)(\S+)} #11
      g = [$1,$2,$3,$4,$5,$6]
      ancho = g[0]
      serie = g[1]
      llanta = g[3]
      tube = nil
      vel = g[5].scan(/[A-Z]+/)[0]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\S+)(?:-|:)(\S+)(?:\s|:)(\S+)(?:\s|:)(\S+)} #12
      g = [$1,$2,$3,$4]
      ancho = g[0]
      serie = nil
      llanta = g[1]
      tube = g[2]
      vel = nil
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, true]
    elsif rueda =~ %r{(\d+)(?:\s|:)(\D)(?:\s|:)(\d+[A-Z])(?:\s|:)(\D+)(?:\s|:)(\S+)(?:\s|:)(\d+)(?:/|:)(\d+[A-Z])} #13
      g = [$1,$2,$3,$4,$5,$6,$7]
      ancho = g[0]
      serie = nil
      llanta = g[2]
      tube = g[3]
      vel = g[6].scan(/[A-Z]+/)[0]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\d+)(?:\s|:)(\D)(?:\s|:)(\S+)(?:\s|:)(\D+)(?:\s|:)(\d+)(?:/|:)(\d+[A-Z])} #14
      g = [$1,$2,$3,$4,$5,$6]
      ancho = g[0]
      serie = nil
      llanta = g[2]
      tube = g[3]
      vel = g[5].scan(/[A-Z]+/)[0]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\d+)(?:/|:)(\d+)(?:\s|:)(\S+)(?:\s|:)(\S+)(?:\s|:)(\S+)} #15
      g = [$1,$2,$3,$4,$5]
      ancho = g[0]
      serie = g[1]
      llanta = g[3]
      tube = nil
      vel = g[4].scan(/[A-Z]+/)[0]
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\S+)(?:\s|:)(\D)(?:\s|:)(\S+)(?:\s|:)(\S+)} #16
      g = [$1,$2,$3,$4]
      ancho = g[0]
      serie = nil
      llanta = g[2]
      tube = nil
      vel = nil
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    elsif rueda =~ %r{(\d+)(?:X|:)(\d+)} #17
      g = [$1,$2]
      ancho = g[0]
      serie = nil
      llanta = g[2]
      tube = nil
      vel = nil
      marca = read_taxon(rueda)
      [ancho, serie, llanta, vel, tube, marca, false]
    else
      @no_leidos << [rueda]
    end
  end
  
  def read_taxon(rueda)
   str = rueda.split
   inter = str & @taxons
   @taxons.find_index(inter[0]) 
  end
  
  def read_tube(tube)
    if tube.nil?
      return nil
    else
      return @tubes.find_index(tube)
    end  
  end
  
  def set_width(row)
    ancho = row[0]
    ancho == "" ? ancho : @widths.index(ancho) + 1
  end
  
  def set_serial(row)
    serie = row[1]
    serie == nil ? serie : @series.index(serie) + 1
  end
  
  def set_innertube(row)
    llanta = row[2]
    llanta == nil ? llanta : @llantas.index(llanta) + 1
  end
  
  def set_speed_code(row)
    vel = row[3]
    vel == nil ? vel : @vel.index(vel) + 1
  end
  
  def set_season(row)
    3
  end
  
  def set_brand(row)
    marca = row[5]
    marca = @marcas.index(marca)
    if marca.nil?
      31
    else
      marca + 1
    end
  end
  
  def set_stock(stock)
    if stock.include?("<")
      stock.delete("<").to_i - 1
    elsif stock.include?(">")
      stock.delete(">").to_i
    else
      stock
    end
  end
  
  def set_catalog
    3
  end
  
end
