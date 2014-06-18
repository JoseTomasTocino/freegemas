/**
 * @file animacion.h
 * 
 * @author José Tomás Tocino García
 * @date 2010
 *
 * 
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



#ifndef _ANIMACION_H_
#define _ANIMACION_H_

#include <cmath>
#include <iostream>

using namespace std;

/**
 * @class Animacion
 *
 * @brief Calcula y devuelve valores para realizar animaciones.
 *
 * El funcionamiento es sencillo. Creamos un objeto Animación al que le indicamos el
 número de parámetros que nos interesaría animar. Por ejemplo, para la posición de un objeto,
 lo usual es animar la posición X y la posición Y. Además, al constructor de la animación
 le indicamos la duración de la animación, la ecuación a seguir (según queramos imitar
 un movimiento de aceleración o deceleración) y la espera inicial antes de comenzar la animación.
 \code
 Animacion miAnimacion (2, 30, Animacion::tEaseInQuad, 0);
 \endcode

 Seguidamente, por cada parámetro tendremos que indicar cuál es el valor inicial y final de la
 animación:
 \code
 // Parámetro 0 (la X en el ejemplo), de 10 a 150
 miAnimacion . set(0, 10, 150);

 // Parámetro 1 (la Y) de 25 a 40
 miAnimacion . set(1, 25, 40);
 \endcode

 Ahora, para que la animación vaya avanzando habrá que ir llamando al método #update;
 el método #get nos servirá para leer el valor de cada parámetro y aplicarlo a nuestro programa.
 \code
 miAnimacion . update();
 cout << "Posición horizontal: " << miAnimacion.get(0) << "\n"
      << "Posición vertical: " << miAnimacion.get(1) << endl;
\endcode

 * Contiene una serie de ecuaciones con las que lograr efectos de aceleración y deceleración en las animaciones.
 *
 * 
 *
 * @author José Tomás Tocino García <theom3ga@gmail.com> 
 *
 */


class Animacion{
    
public:
    /// Diferentes tipos de animaciones
    enum tipoAnim {tEaseInQuad, tEaseOutQuad, tEaseInOutQuad,
		   tEaseInCubic, tEaseOutCubic, tEaseInOutCubic,
		   tEaseInQuart, tEaseOutQuart, tEaseInOutQuart,
		   tEaseOutBack, tLinear};

    enum atribAnim{ tNada, tAlpha, tPos, tAlphaPos };

private:

    /// Número de atributos a animar
    int numAttr;

    /// Duración de la animación
    int duracion;

    /// Espera inicial antes de iniciar la animación
    int esperaInicial;

    /// Contador del tiempo pasado
    int time;

    /// Vector de posiciones iniciales
    int * inicial;

    /// Vector de posiciones finales
    int * final;

    /// Vector de recorridos (diferencia entre final e inicial)
    int * change;

    /// Vector de posiciones actuales
    float * actual;

    /// Tipo de animación a realizar
    tipoAnim anim;

    /// Puntero a la función de animación
    float (*puntFun) (float, float, float, float);
    
public:
    /**
     * @brief Crea una nueva animación
     * 
     * Se inicializan los vectores para cada uno de los atributos a animar.
     *
     * @param n Número de atributos en los que se hará la animación.
     * @param d Duración de la animación.
     * @param anim Tipo de animación.
     * @param e Espera inicial antes de empezar la animación.
     *
     */

    Animacion(int n, int d, tipoAnim anim = tEaseInQuad, int e = 0);

    ///@{
    ///@name Control del flujo de la animación

    /**
     * @brief Reinicia la animación al estado inicial
     */
    void init();

    /**
     * @brief Coloca la animación en su estado final
     */
    void end();

    /**
     * @brief Comprueba si la animación ha terminado.
     * @return Verdadero si la animación ha terminado.
     */
    bool finished();

    ///@}

    ///@{
    ///@name Configuración de los valores de los atributos que serán animados.

    /**
     * @brief Devuelve el valor actual del atributo indicado.
     *
     * @param i El índice del atributo cuyo valor hay que consultar.
     * @return El valor del atributo.
     *
     */
    float get(int i);

    /**
     * @brief Inicializa los valores inicial y final para el atributo i-ésimo.
     *
     * @param i Atributo al que cambiarle los valores.
     * @param v1 Valor inicial del atributo.
     * @param v2 Valor final del atributo.
     *
     */
    void set(int i, int v1, int v2);

    /**
     * @brief Inicializa el valor inicial para el atributo i-ésimo.
     *
     * @param i Atributo al que le modificaremos el valor inicial.
     * @param v Valor inicial del atributo.
     *
     */
    void setInicial(int i, int v);

    /**
     * @brief Inicializa el valor final del atributo i-ésimo.
     *
     * @param i Atributo al que le modificaremos el valor final.
     * @param v Valor final del atributo.
     * @return 
     *
     */
    void setFinal(int i, int v);

    void reverse();

    ///@}


    ///@{
    ///@name Opciones de la animación

    /**
     * @brief Selecciona la ecuación de la animación.
     *
     * @param a Ecuación a asignar.
     */
    void setTipoAnimacion(tipoAnim a);

    /**
     * @brief Asigna la duración de la animación.
     * @param d Duración de la animación.
     */
    void setDuracion(int d) { duracion = d; }

    /**
     * @brief Asigna el tiempo de espera de la animación.
     * @param e Tiempo de espera.
     */

    void setEspera(int e) { esperaInicial = e; }
    ///@}


    /**
     * @brief Actualiza la animación un paso.
     */
    void update(bool a = true);


    /**
     * @name Ecuaciones de tweening
     * Todas las ecuaciones de tweening reciben cuatro argumentos:
     * - Tiempo pasado.
     * - Valor inicial.
     * - Diferencia entre el valor final y el inicial.
     * - Duración de la animación.
     */

    //@{


    static float easeLinear(float t, float b, float c, float d);

    static float easeInQuad (float t, float b, float c, float d);
    static float easeOutQuad(float t, float b, float c, float d);
    static float easeInOutQuad(float t, float b, float c, float d);
    
    static float easeInCubic(float t, float b, float c, float d) ;
    static float easeOutCubic(float t, float b, float c, float d) ;
    static float easeInOutCubic(float t, float b, float c, float d);


    static float easeInQuart(float t, float b, float c, float d) ;
    static float easeOutQuart(float t, float b, float c, float d) ;
    static float easeInOutQuart(float t, float b, float c, float d);

    static float easeOutBack(float t, float b, float c, float d);
    //@}

    /// Libera la memoria de los diferentes vectores.
    ~Animacion();
};

#endif /* _ANIMACION_H_ */
