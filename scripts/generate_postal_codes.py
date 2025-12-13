#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Irányítószám-település adatok konvertálása Excel fájlból JSON formátumba
"""

import json
import os
import sys
from pathlib import Path

try:
    import pandas as pd
except ImportError:
    print("Hiba: A pandas könyvtár nincs telepítve.")
    print("Telepítés: pip install pandas openpyxl")
    sys.exit(1)

def generate_postal_codes_json():
    """Excel fájl beolvasása és JSON generálása"""
    
    # Fájl útvonalak
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    excel_file = project_root / 'docs' / 'iranyitoszamok.xls'
    output_file = project_root / 'assets' / 'postal_codes.json'
    
    # Ellenőrzés: létezik-e az Excel fájl
    if not excel_file.exists():
        print(f"Hiba: Az Excel fájl nem található: {excel_file}")
        sys.exit(1)
    
    # Assets mappa létrehozása, ha nem létezik
    output_file.parent.mkdir(parents=True, exist_ok=True)
    
    print(f"Excel fájl beolvasása: {excel_file}")
    
    try:
        # Excel fájl beolvasása
        # Próbáljuk meg először openpyxl-lel (.xlsx), majd xlrd-del (.xls)
        try:
            df = pd.read_excel(excel_file, engine='openpyxl')
        except:
            try:
                df = pd.read_excel(excel_file, engine='xlrd')
            except:
                # Ha mindkettő sikertelen, próbáljuk meg anélkül, hogy engine-t adnánk meg
                df = pd.read_excel(excel_file)
        
        print(f"Beolvasott sorok száma: {len(df)}")
        print(f"Oszlopok: {df.columns.tolist()}")
        
        # Adatok feldolgozása
        # Feltételezzük, hogy az első oszlop az irányítószám, a második a település
        # Ha más struktúra van, módosítani kell
        postal_codes = {}
        
        # Keresés az irányítószám és település oszlopokban
        zip_col = None
        city_col = None
        
        # Próbáljuk meg megtalálni az oszlopokat név alapján
        for col in df.columns:
            col_str = str(col).replace('\n', ' ').replace('\r', ' ')
            col_lower = col_str.lower()
            if 'irányítószám' in col_lower or 'irsz' in col_lower or 'zip' in col_lower or 'postal' in col_lower or 'postal code' in col_lower:
                zip_col = col
            if 'település' in col_lower or 'város' in col_lower or 'city' in col_lower or 'place name' in col_lower or 'place' in col_lower:
                city_col = col
        
        # Ha nem találtuk meg név alapján, használjuk az első két oszlopot
        if zip_col is None:
            zip_col = df.columns[0]
        if city_col is None:
            city_col = df.columns[1] if len(df.columns) > 1 else df.columns[0]
        
        print(f"Irányítószám oszlop: {zip_col}")
        print(f"Település oszlop: {city_col}")
        
        # Debug: első néhány sor megjelenítése
        print("\nElső 5 sor adatai:")
        for i, (_, row) in enumerate(df.head(5).iterrows()):
            print(f"  Sor {i+1}: zip={row[zip_col]}, city={row[city_col]}")
        
        # Adatok feldolgozása
        processed_count = 0
        skipped_count = 0
        for _, row in df.iterrows():
            try:
                zip_value = row[zip_col]
                city_value = row[city_col]
                
                # Üres sorok kihagyása
                if pd.isna(zip_value) or pd.isna(city_value):
                    continue
                
                # Irányítószám kezelése (lehet float vagy string)
                if isinstance(zip_value, (int, float)):
                    # Ha float vagy int, konvertáljuk stringgé és távolítsuk el a tizedesvesszőt
                    zip_code_clean = str(int(zip_value)).zfill(4)
                else:
                    zip_code = str(zip_value).strip()
                    # Üres értékek kihagyása
                    if zip_code == '' or zip_code.lower() == 'nan':
                        continue
                    # Irányítószám normalizálása (csak számok)
                    zip_code_clean = ''.join(filter(str.isdigit, zip_code))
                
                # Ha nincs 4 számjegy, kihagyjuk
                if len(zip_code_clean) != 4:
                    continue
                
                city = str(city_value).strip()
                
                # Üres értékek kihagyása
                if city == '' or city.lower() == 'nan':
                    continue
                
                # Település normalizálása (felesleges szóközök eltávolítása)
                city_clean = ' '.join(city.split())
                
                # Település hozzáadása az irányítószámhoz
                if zip_code_clean not in postal_codes:
                    postal_codes[zip_code_clean] = []
                
                # Ha még nincs benne ez a település, hozzáadjuk
                if city_clean not in postal_codes[zip_code_clean]:
                    postal_codes[zip_code_clean].append(city_clean)
                    processed_count += 1
            except Exception as e:
                # Egyedi sor hibája esetén folytatjuk
                skipped_count += 1
                if skipped_count <= 5:  # Csak az első 5 hibát írjuk ki
                    print(f"  Hiba sor feldolgozásánál: {e}")
        
        print(f"\nFeldolgozott sorok: {processed_count}, Kihagyott sorok: {skipped_count}")
        
        # Települések rendezése
        for zip_code in postal_codes:
            postal_codes[zip_code].sort()
        
        print(f"\nFeldolgozott irányítószámok száma: {len(postal_codes)}")
        
        # JSON fájl mentése
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(postal_codes, f, ensure_ascii=False, indent=2)
        
        print(f"JSON fájl sikeresen létrehozva: {output_file}")
        
        # Statisztika
        single_city_count = sum(1 for cities in postal_codes.values() if len(cities) == 1)
        multi_city_count = sum(1 for cities in postal_codes.values() if len(cities) > 1)
        
        print(f"\nStatisztika:")
        print(f"  - 1 településes irányítószámok: {single_city_count}")
        print(f"  - Több településes irányítószámok: {multi_city_count}")
        
        return True
        
    except Exception as e:
        print(f"Hiba történt: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == '__main__':
    success = generate_postal_codes_json()
    sys.exit(0 if success else 1)

