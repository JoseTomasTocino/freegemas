/**
 * @file ecuaciones.cpp
 *
 * @author José Tomás Tocino García
 * @date 2010
 *
 * Implementación para las ecuaciones de animación
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

#include "Animation.h"

// ######################################################
// Ecuaciones de tweening

float Animacion::easeLinear(float t, float b, float c, float d){
    return c * t / d + b;
}

float Animacion::easeInQuad (float t, float b, float c, float d) {
    t/=d;
    return c*t*t + b;
}

float Animacion::easeOutQuad(float t, float b, float c, float d) {
    t/=d;
    return -c *(t)*(t-2) + b;
}

float Animacion::easeInOutQuad(float t, float b, float c, float d) {
    t /= d/2;
    if (t < 1){
	return c/2*t*t + b;
    }else{
	--t;
	return -c/2 * ((t)*(t-2) - 1) + b;
    }
}

float Animacion::easeInCubic(float t, float b, float c, float d) {
    t/=d;
    return c*(t)*t*t + b;
}

float Animacion::easeOutCubic(float t, float b, float c, float d) {
    t=t/d-1;
    return c*(t*t*t + 1) + b;
}

float Animacion::easeInOutCubic(float t, float b, float c, float d) {
    t/=d/2;
    if ((t) < 1){
	return c/2*t*t*t + b;
    }else{
	t-=2;
	return c/2*((t)*t*t + 2) + b;
    }
}


float Animacion::easeInQuart(float t, float b, float c, float d) {
    t/=d;
    return c*(t)*t*t*t + b;
}

float Animacion::easeOutQuart(float t, float b, float c, float d) {
    t=t/d-1;
    return -c * ((t)*t*t*t - 1) + b;
}

float Animacion::easeInOutQuart(float t, float b, float c, float d) {
    t/=d/2;
    if ((t) < 1){
	return c/2*t*t*t*t + b;
    }else{
	t-=2;
	return -c/2 * ((t)*t*t*t - 2) + b;
    }
}

float Animacion::easeOutBack(float t, float b, float c, float d){
//    float s = 1.70158;
    float s = 1.3;
    t = t/d - 1;
    return c*(t*t*((s+1)*t + s) + 1) + b;
}

