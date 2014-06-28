/**
 * @file log.h
 * 
 * @author José Tomás Tocino García
 * @date 2010
 *
 * Clase para el log
 * 
 * Copyright (C) 2010 José Tomás Tocino García <theom3ga@gmail.com>
 * 
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301, USA.
 */

#ifndef _LOG_H_
#define _LOG_H_

#include <iostream>
#include <sstream>
#include <cstdio>
#include <string>

using namespace std;

/// Añade Función:(Archivo: linea) desde donde fué llamada.
#define LOC()  string(__FUNCTION__) + " :(" + __FILE__ + ":" +  std::to_string(__LINE__) + ")  " 
//#define LOC()  << __FUNCTION__ << " :(" << __FILE__ << ":" <<  __LINE__ << ")  " 

/**
 * Añade variable == valor. (x) debe tener definido el operador << obviamente.
 */
#define VARV(x) #x << " = " << (x)


enum TLogLevel {logERROR, logWARNING, logINFO, logDEBUG};

/**
 * @class Log
 *
 * @brief Gestiona el log del programa.
 *
 * Utiliza sintaxis de flujo para facilitar el uso. Existen cuatro niveles de log, aunque por ahora
 * no se diferencian en nada más que en el nombre.
 *
 * Para usar el log, la sintaxis es la siguiente:
 * \code
 * Log().Get(logDEBUG) << "Mensaje";
 * \endcode
 * No es necesario añadir un salto de línea al final, el manejador del log lo inserta automáticamente.
 *
 * @author José Tomás Tocino García <theom3ga@gmail.com> 
 *
 */


class Log{
public:
    /**
     * @brief Devuelve el flujo para el nivel indicado
     *
     * @param level Nivel de log del mensaje
     * @return Flujo en el que insertar los mensajes.
     *
     */
    std::ostringstream& Get(TLogLevel level = logINFO);

    /**
     * @brief Devuelve una cadena con el texto correspondiente al nivel indicado.
     *
     * @param T Nivel de log.
     * @return Cadena con el nivel escrito.
     *
     */
    static string ToString(TLogLevel T);

    /**
     * @brief Devuelve una cadena con el texto de log estándar para constructores.
     * Escrito por conveniencia para unificar el logging de constructores y destructores.
     *
     * @param s Nombre de la clase cuyo constructor está siendo llamado
     * @return Cadena con el texto para hacer log de la construcción
     *
     */
    static string CON(string s);

    /** 
     * @brief Devuelve una cadena con el texto de log estándar para destructores.
     * Escrito por conveniencia para unificar el logging de constructores y destructores.
     *
     * @param s Nombre de la clase cuyo destructor está siendo llamado.
     * @return Cadena con el texto para hacer log de la destrucción.
     *
     */
    static string DES(string s);

    static bool salida;

    /**
     * @brief Vuelca el flujo con los mensajes de log en el destino indicado, por ahora la salida estándar.
     */
    ~Log();

    //@{
    ///@name Constantes de colores

    /// Constantes de cadena con códigos de colores para terminales UNIX. No se
    /// ha probado en otros sistemas.
    static string cRojo, cVerde, cAzul, cAmar, cLila;

    /// Colores en negrita
    static string nRojo, nVerde, nAzul, nAmar, nLila;

    /// Colores en el fondo
    static string bRojo, bVerde, bAzul, bAmar, bLila;

    // Default color
    static string cDef;
    //@}

protected:
    /// Flujo en el que se vuelcan los mensajes antes de ser enviados al destino final.
    std::ostringstream os;

};

#define lDEBUG Log().Get(logDEBUG)
#define lERROR Log().Get(logERROR)

#endif /* _LOG_H_ */
