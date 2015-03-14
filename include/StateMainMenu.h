#ifndef _STATEMAINMENU_H_
#define _STATEMAINMENU_H_

#include "State.h"
#include "JewelGroupAnim.h"

#include "go_image.h"
#include "go_font.h"


#include <vector>

using namespace std;

class Game;

/**
 * @class StateMainMenu
 *
 * @brief State for the main menu
 *
 * It manages the buttons of the main menu. The menu items are largely
 * dynamic. Also, there's an additional class that manages the animations of the
 * group of jewels that appear for decoration.
 *
 * @author José Tomás Tocino García <theom3ga@gmail.com>
 *
 */


class StateMainMenu : public State{
public:

    /// Creates a new StateMainMenu
    StateMainMenu(Game * p);

    /// It controls the animations and the transitions
    void update();

    /// Draws the different elements
    void draw();

    /**
     * @brief It gets called whenever the user presses a button.
     *
     * The user can press Up, Down and Return to select the menu entries, as
     * well as the mouse.
     *
     */
    void buttonDown(SDL_Keycode B);

    void mouseButtonDown(Uint8 button);

    ~StateMainMenu();

private:

    /// Possible states of the transition
    enum transitionState{ TransitionIn,
			  Active,
			  TransitionOut };

    /// Current transition state
    transitionState mCurrentTransitionState;

    /// Current step of the animation
    int mAnimationCurrentStep;

    /// Logo animation's total steps
    int mAnimationLogoSteps;

    /// General animation's total steps
    int mAnimationTotalSteps;

    /// Image for the background
    GoSDL::Image mImgBackground;

    /// Image for the logo
    GoSDL::Image mImgLogo;

    /// Image for the higlight of the menu entry
    GoSDL::Image mImgHighl;

    /// Font for the menu entries
    GoSDL::Font mFont;

    /// Class for the animation of the decorating jewels
    JewelGroupAnim mJewelAnimation;

    /// Current highlighted option
    int mMenuSelectedOption;

    /// List of menu options.
    vector<string> mMenuTargets;
    vector<GoSDL::Image> mMenuRenderedTexts;
    vector<GoSDL::Image> mMenuRenderedShadows;

    /// It gets executed when the user choses an option. It changes the state
    ///  to the proper one.
    void optionChosen();

    /// @{
    /// @name Coordinates of the menu elements
    int mMenuYStart, mMenuYEnd, mMenuYGap;
    /// @}

};

#endif /* _STATEMAINMENU_H_ */
