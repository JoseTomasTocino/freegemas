#include "board.h"

#include <cstdlib>
#include <ctime>
#include <iostream>

Board::Board(){
    lDEBUG << Log::CON("Board");
    generate();
}

void Board::generate(){
    std::srand((unsigned int) time(0));

    bool repeat = false;

    do {
        // lDEBUG << "### Generating...";
        repeat = false;

        for (int i = 0; i < 8; ++i)
        {
            for (int j = 0; j < 8; ++j)
            {
                squares[i][j] = static_cast<tSquare>(rand() % 7 + 1);
                squares[i][j].mustFall = true;
                squares[i][j].origY = rand() % 8 - 7;
                squares[i][j].destY = j - squares[i][j].origY;
            }
        }
        if(!check().empty()){
            // lDEBUG << "Generated board has matches. Repeating...";
            repeat = true;
        }

        else if(solutions().empty()){
            // lDEBUG << "Generated board has no solutions. Repeating...";
            repeat = true;
        }

    } while(repeat);
    // Regenera si hay alguna solución directa o si es imposible

    // lDEBUG << "The generated board has no direct matches but some possible solutions.";
}

void Board::swap(int x1, int y1, int x2, int y2){
    tSquare temp = squares[x1][y1];

    squares[x1][y1] = squares[x2][y2];
    squares[x2][y2] = temp;
}

void Board::del(int x, int y){
    squares[x][y] = sqEmpty;
}

vector<coord> Board::solutions(){
    vector<coord> resultados;

    if(!check().empty()){
        resultados.push_back(coord(-1,-1));
        return resultados;
    }


    /*
       Checkemos todos los posibles boards
       (49 * 4) + (32 * 2) aunque hay muchos repetidos
    */

    Board temp = *this;

    for(int x = 0; x < 8; ++x){
        for(int y = 0; y < 8; ++y){

            // Cambiar con superior y check
            if(y > 0){
                temp.swap(x,y, x,y-1);
                if(!temp.check().empty()){
                    resultados.push_back(coord(x,y));
                }
                temp.swap(x,y, x,y-1);
            }

            // Cambiar con inferior y check
            if(y < 7){
                temp.swap(x, y, x, y+1);
                if(!temp.check().empty()){
                    resultados.push_back(coord(x,y));
                }
                temp.swap(x, y, x, y+1);
            }

            // Cambiar con celda izquierda y check
            if(x > 0){
                temp.swap(x, y, x - 1, y);
                if(!temp.check().empty()){
                    resultados.push_back(coord(x,y));
                }
                temp.swap(x, y, x - 1, y);
            }

            // Cambiar con celda derecha y check
            if(x < 7){
                temp.swap(x, y, x + 1, y);
                if(!temp.check().empty()){
                    resultados.push_back(coord(x,y));
                }
                temp.swap(x, y, x + 1, y);
            }


        }
    }

    return resultados;

}

MultipleMatch Board::check(){
    //lDEBUG << "Checking board...";

    int k;

    MultipleMatch matches;

    // First, we check each row (horizontal)
    for(int y = 0; y < 8; ++y){

        for(int x = 0; x < 6; ++x){

            Match currentRow;
            currentRow.push_back(coord(x,y));

            for(k = x+1; k < 8; ++k){
                if(squares[x][y] == squares[k][y] &&
                   squares[x][y] != sqEmpty){
                    currentRow.push_back(coord(k,y));
                }else{
                    break;
                }
            }

            if(currentRow . size() > 2){
                matches.push_back(currentRow);
            }

            x = k - 1;
        }
    }

    for(int x = 0; x < 8; ++x){
        for(int y = 0; y < 6; ++y){

            Match currentColumn;
            currentColumn.push_back(coord(x,y));

            for(k = y + 1; k < 8; ++k){
                if(squares[x][y] == squares[x][k] &&
                   squares[x][y] != sqEmpty){
                    currentColumn.push_back(coord(x,k));
                }else{
                    break;
                }
            }

            if(currentColumn.size() > 2){
                matches.push_back(currentColumn);
            }

            y = k - 1;
        }
    }

    return matches;
}

ostream& operator <<(ostream& out, Board & B){
    for(int i = 0; i < 8; ++i){
        for(int j = 0; j < 8; ++j){
            out << B.squares[j][i] << " ";
        }
        out << endl;
    }

    return out;
}

void Board::calcFallMovements(){
    //lDEBUG << "Board::calcFallMovements";

    for(int x = 0; x < 8; ++x){

        // De abajo a arriba
        for(int y = 7; y >= 0; --y){

            // origY guarda la posición en el inicio de la caida
            squares[x][y].origY = y;

            // Si la casilla es vacía, bajamos todas las squares por encima
            if(squares[x][y] == sqEmpty){

                for(int k = y-1; k >= 0; --k){
                    squares[x][k].mustFall = true;
                    squares[x][k].destY ++;

                }
            }
        }
    }
}

void Board::applyFall(){
    //lDEBUG << "Board::applyFall";

    for(int x = 0; x < 8; ++x){
        // Desde abajo a arriba para no sobreescribir squares

        for(int y = 7; y >= 0; --y){
            if(squares[x][y].mustFall && squares[x][y] != sqEmpty){
                int y0 = squares[x][y].destY;

                squares[x][y + y0] = squares[x][y];
                squares[x][y] = sqEmpty;
            }
        }
    }
}

void Board::fillSpaces(){

    //lDEBUG << "Board::fillSpaces";

    for(int x = 0; x < 8; ++x){
        // Contar cuántos espacios hay que bajar
        int saltos = 0;

        for(int y = 0; y < 8; ++y){
            if(squares[x][y] != sqEmpty) break;
            saltos ++;
        }

        for(int y = 0; y < 8; ++y){
            if(squares[x][y] == sqEmpty) {

                squares[x][y] = static_cast<tSquare> ( rand() % 7 + 1 );

                squares[x][y].mustFall = true;
                squares[x][y].origY = y - saltos;
                squares[x][y].destY = saltos;
            }
        }
    }
}

void Board::endAnimations(){
    for(int x = 0; x < 8; ++x){
        for(int y = 0; y < 8; ++y){
            squares[x][y].mustFall = false;
            squares[x][y].origY = y;
            squares[x][y].destY = 0;
        }
    }
}

Board::~Board(){

}

