# encoding: UTF-8
require 'csv'

class ImportTiresFromGane
  
  def initialize()
    @agent = Mechanize.new
  end
  
  def run
    if login
      read_from_gane
      import_from_csv
    end
  end
  
  def read_from_gane
    str = "http://galaicoasturianadeneumaticos.distritok.com/sqlcommerce/disenos/plantilla1/seccion/Catalogo.jsp?idIdioma=&idTienda=50&cPath=61"
    sch = ".//table[@class='result']//tr//td[@class='result_right']//a[@title='Siguiente ']"
    total = links = []
    while !str.empty?
      page = @agent.get(str).search(".//table[@class='tableBox_output']//tr")
      page.each do |d|
        t = d.search("td[@width='900']//a").text
        r = d.search("td//span[@class='linCat']").map {|x| x.text}
        unless r.empty?
          if r[1] == "Consultar"
              p = c = pf = 0
          else
            s = r[0]
            p = r[1].to_s.delete("€").lstrip
            k = r[2].to_s.delete("%").lstrip
            pf = r[3].to_s.delete("€").lstrip
            puts "Stock es #{p}. PVP final es #{pf}"
          end
          total << [t, p, c, pf]
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
  
  def import_from_csv
    final = "#{Rails.root}/vendor/products/listado-neumaticos.csv"
    CSV.open(@final, "wb") do |row|
      @total.each do |element|
        row << element
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
  
end
