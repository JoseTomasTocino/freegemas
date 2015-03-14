#include "BaseButton.h"

#include "go_font.h"

BaseButton::BaseButton() { }


void BaseButton::set (GoSDL::Window * parentWindow, std::string caption, std::string iconPath)
{
    mParentWindow = parentWindow;

    // Load the background image
    mImgBackground.setWindowAndPath(mParentWindow, "media/buttonBackground.png");

    // Set the flag
    mHasIcon = iconPath != "";

    // Load the icon image
    if (mHasIcon)
    {
        mImgIcon.setWindowAndPath(mParentWindow, "media/" + iconPath);
    }

    setText(caption);
}

void BaseButton::setText(std::string caption)
{
    // Load the font for the button caption
    GoSDL::Font textFont;
    textFont.setAll(mParentWindow, "media/fuenteNormal.ttf", 27);

    // Generate the button caption texture
    mImgCaption = textFont.renderText(caption, {255, 255, 255, 255});
    mImgCaptionShadow = textFont.renderText(caption, {0, 0, 0, 255});

    // Calculate the position of the text
    if (mHasIcon)
    {
        mTextHorizontalPosition = 40 + (mImgBackground.getWidth() - 40) / 2 - mImgCaption.getWidth() / 2;
    }

    else
    {
        mTextHorizontalPosition = mImgBackground.getWidth() / 2 - mImgCaption.getWidth() / 2;
    }
}


void BaseButton::draw(int x, int y, double z)
{
    mLastX = x;
    mLastY = y;

    if (mHasIcon)
    {
        mImgIcon.draw(x + 7, y, z + 1);
    }

    mImgCaption.draw(x + mTextHorizontalPosition, y + 5, z + 2);
    mImgCaptionShadow.draw(x + mTextHorizontalPosition + 1, y + 7, z + 1,  1, 1, 1, 128);

    mImgBackground.draw(x, y, z);

}

bool BaseButton::clicked(unsigned int mX, unsigned int mY)
{
    if(mX > mLastX && mX < mLastX + mImgBackground.getWidth() &&
       mY > mLastY && mY < mLastY + mImgBackground.getHeight())
       {
        return true;
    }else
    {
        return false;
    }
}
