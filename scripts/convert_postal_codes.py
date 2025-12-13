#!/usr/bin/env python3
"""
Irányítószám Excel fájl konvertálása JSON formátumba
Az Excel fájlból kinyeri az irányítószámokat és településeket,
majd Map<String, List<String>> struktúrában JSON fájlba menti.
"""

import json
import sys
import os

# Próbáljuk meg importálni a szükséges könyvtárakat
try:
    import pandas as pd
except ImportError:
    print("ERROR: pandas könyvtár nincs telepítve!")
    print("Telepítés: pip install pandas openpyxl xlrd")
    sys.exit(1)

def convert_excel_to_json(excel_path, output_path):
    """
    Excel fájl beolvasása és JSON formátumba konvertálása
    
    Args:
        excel_path: Az Excel fájl elérési útja
        output_path: A kimeneti JSON fájl elérési útja
    """
    try:
        # Excel fájl beolvasása
        # xlrd engine-t használunk .xls fájlokhoz
        print(f"Excel fájl beolvasasa: {excel_path}")
        # Próbáljuk először az xlrd-t (.xls fájlokhoz)
        try:
            df = pd.read_excel(excel_path, engine='xlrd')
        except Exception:
            # Ha nem működik, próbáljuk az openpyxl-t (.xlsx fájlokhoz)
            df = pd.read_excel(excel_path, engine='openpyxl')
        
        # Oszlopok neveinek kiírása debug céljából
        print(f"Oszlopok: {df.columns.tolist()}")
        print(f"Első néhány sor:\n{df.head()}")
        
        # Csak az első két oszlopot használjuk
        if len(df.columns) < 2:
            raise ValueError("Az Excel fájlnak legalább 2 oszlopra van szüksége")
        
        zip_col = df.columns[0]
        city_col = df.columns[1]
        
        print(f"Iranyitoszam oszlop: {zip_col}")
        print(f"Telepules oszlop: {city_col}")
        
        # Adatok feldolgozása
        postal_codes = {}
        
        for _, row in df.iterrows():
            # Üres vagy NaN értékek kihagyása
            if pd.isna(row[zip_col]) or pd.isna(row[city_col]):
                continue
            
            # Irányítószám feldolgozása (float típusú lehet, pl. 8128.0)
            zip_value = row[zip_col]
            if pd.isna(zip_value):
                continue
            
            # Konvertálás stringgé, majd float kezelése
            if isinstance(zip_value, (int, float)):
                zip_code = str(int(zip_value)).zfill(4)  # 4 karakterre töltjük ki nullákkal
            else:
                zip_code = str(zip_value).strip()
                # Csak számjegyek kinyerése
                zip_code = ''.join(filter(str.isdigit, zip_code))
            
            if len(zip_code) != 4:
                continue
            
            # Település feldolgozása
            city = str(row[city_col]).strip()
            if not city or city == 'nan':
                continue
            
            # Település normalizálása
            if not city or city == 'nan':
                continue
            
            # Hozzáadás a dictionary-hez
            if zip_code not in postal_codes:
                postal_codes[zip_code] = []
            
            # Ha még nincs benne a település, hozzáadjuk
            if city not in postal_codes[zip_code]:
                postal_codes[zip_code].append(city)
        
        # Rendezés település szerint
        for zip_code in postal_codes:
            postal_codes[zip_code].sort()
        
        # JSON fájlba mentés
        print(f"\nKonvertálva: {len(postal_codes)} egyedi irányítószám")
        print(f"JSON fájl mentése: {output_path}")
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(postal_codes, f, ensure_ascii=False, indent=2)
        
        print("Sikeres konverzio!")
        
        # Statisztika
        single_city = sum(1 for cities in postal_codes.values() if len(cities) == 1)
        multi_city = sum(1 for cities in postal_codes.values() if len(cities) > 1)
        print(f"\nStatisztika:")
        print(f"  - Egy telepules: {single_city}")
        print(f"  - Tobb telepules: {multi_city}")
        
        return True
        
    except Exception as e:
        print(f"HIBA tortent: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    # Fájl elérési utak
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    
    excel_path = os.path.join(project_root, "docs", "iranyitoszamok.xls")
    output_path = os.path.join(project_root, "assets", "postal_codes.json")
    
    # Ellenőrzés, hogy létezik-e az Excel fájl
    if not os.path.exists(excel_path):
        print(f"HIBA: Az Excel fajl nem talalhato: {excel_path}")
        sys.exit(1)
    
    # Ellenőrzés, hogy létezik-e az assets könyvtár
    assets_dir = os.path.dirname(output_path)
    if not os.path.exists(assets_dir):
        print(f"Az assets könyvtár létrehozása: {assets_dir}")
        os.makedirs(assets_dir, exist_ok=True)
    
    # Konverzió
    success = convert_excel_to_json(excel_path, output_path)
    
    if success:
        print(f"\nSIKERES: A JSON fajl sikeresen letrejott: {output_path}")
    else:
        print(f"\nHIBA: A konverzio sikertelen volt")
        sys.exit(1)

