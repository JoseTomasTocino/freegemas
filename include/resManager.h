/**
 * @file resManager.h
 * 
 * @author José Tomás Tocino García
 * @date 2010
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


#ifndef _RESMANAGER_H_
#define _RESMANAGER_H_

#include <Gosu/Gosu.hpp>

#include <boost/shared_ptr.hpp>
#include <boost/unordered_map.hpp>

#include <string>
using namespace std;

#include "sdlfont.h"

#define ResMgr ResourceManager::instance()

/**
 * @class ResourceManager
 *
 * @brief Manages resources automatically collecting garbage.
 *
 * It uses shared pointers to manage resources ownership and usage,
 * deleting every unused resource. It collects garbage every time a
 * new resource is requested, or when collectGarbage() is manually
 * called.
 *
 * This class is a Singleton, so in order to
 * access any of its methods you can use:
 *
 * \code
 * ResourceManager::instance() -> method();
 * // or using the macro ResMgr
 * ResMgr -> method();
 * \endcode
 *
 * This class requires initialization to properly load the assets. Use the following line
 * as soon as your program starts from your main window class:
 *
 * \code
 * ResourceManager::instance() -> init(graphics());
 * \endcode
 *
 * @author José Tomás Tocino García <theom3ga@gmail.com> 
 *
 */

class ResourceManager{
public:

    /// Returns the instance of the resource manager.
    static boost::shared_ptr<ResourceManager> instance();

    static void delInstance();

    /// Initializes the resource manager.
    void init(Gosu::Graphics & g_);

    /// Returns a shared_ptr to the requested image.
    boost::shared_ptr<Gosu::Image> getImage(wstring path);

    /// Returns a shared_ptr to the requested font.
    boost::shared_ptr<CustomFont> getFont(wstring path, int size);

    /// Checks usage of resources and collects garbage, freeing unused resources.
    void collectGarbage(wstring bypass = L"");

    ~ResourceManager();
protected:

    /// Protected constructor to avoid multi-instantiation
    ResourceManager();

private:
    /// Map of loaded images
    boost::unordered_map<wstring, boost::shared_ptr<Gosu::Image> > loadedImages;

    /// Map of loaded fonts
    boost::unordered_map<wstring, boost::shared_ptr<CustomFont> > loadedFonts;

    /// Iterator type definition for the map of images
    typedef boost::unordered_map<wstring, boost::shared_ptr<Gosu::Image> >::iterator imgMapIterator;

    /// Iterator type definition for the map of fonts
    typedef boost::unordered_map<wstring, boost::shared_ptr<CustomFont> >::iterator fontMapIterator;

    /// Pointer to graphics object
    Gosu::Graphics * g;

    /// Instance of the class
    static boost::shared_ptr<ResourceManager> pointerInstance;
};

#endif /* _RESMANAGER_H_ */
